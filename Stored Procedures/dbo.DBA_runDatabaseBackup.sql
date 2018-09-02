SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2018 Raul Gonzalez, @SQLDoubleG
-- All rights reserved.
--   
-- You may alter this code for your own *non-commercial* purposes. You may
-- republish altered code as long as you give due credit.
--   
-- THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
-- ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
-- TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
-- PARTICULAR PURPOSE.
--
-- ============================================= 
-- Author:		Raul Gonzalez 
-- Create date: 16/05/2013 
-- Description:	Run Full backups for databases  
--				This Script does: 
--					- Backup databases according the current settings kept in [DBA].[dbo].[DatabaseInformation] and [DBA].[dbo].[InstanceInformation]. 
--					- Delete old backups and transaction logs when parameter @deleteOldBackups = 1 
-- 
-- Change Log:	 
--				07/08/2013 RAG	- Changed the name format to YYYYMMDD_hhmm to be able to have more than one backup for the same day 
--				15/08/2013 RAG	- Included optional parameter @path to be able to specify a path instead of the default one (ETFMS WIP Backup) 
--				07/10/2013 RAG	- Moved all the logic to delete files to [dbo].[DBA_deleteOldBackups] 
--				22/10/2013 RAG	- Changed the backup file extension to .COPY_ONLY instead of .bak when @isCopyOnly = 1, so these backups will be never 
--									taken into play when deleting them automatically through a SP 
--				22/10/2013 RAG	- Change the value of @timeText to use the new function [DBA].[dbo].[formatTimeToText]() which will be used  
--									from now on for backups (full & trn) 
--				22/10/2013 RAG	- Removed WITH CHEKSUM when COMPRESSION is on as that is the default behaviour 
--									http://technet.microsoft.com/en-us/library/ms186865(v=sql.105).aspx 
--				10/01/2013 RAG	- Excluded database snapshots 
--				28/10/2015 RAG	- Changed INIT to NOINIT, http://www.sqldoubleg.com/2015/10/28/daylight-savings-end-affects-not-only-you-but-your-sql-server-too/ 
--				19/02/2016 RAG	- Added extra 0 to file number for multi files backups (more than 9 files) 
--				21/04/2016 RAG	- Renamed to [dbo].[DBA_runDatabaseBackup]as now will handle full and differential backups too 
--								- New BackupSchedule on [DBA].[dbo].[DatabaseInformation] will be CHAR(7) like 'DDDDDDD'  
--									reflecting Sun-Sat backup schedule, D for Database, I for Differential (as per [msdb].[dbo].[backupset] column [type] 
--				16/06/2016 RAG	- Changed [backupPath] and [fileDiskPath] to NVARCHAR(512) 
--				04/07/2016 RAG	- Added parameter @weekDayOverride which gives functionality to override the day of the week we want to run the process for. 
--								- Removed @isWeekly since schedules are defined for the whole week in a char(7) 
--								- Assign default values when some parameters are NULL and cannot be 
--				18/07/2016	RAG	- Added validation for PRIMARY replicas in case there are Availability Groups configured, only for scheduled backups 
--				14/09/2016	RAG	-  
--									Removed validation for PRIMARY replicas. 
--									Databases are now coming from [dbo].[DBA_getDatabasesMaintenanceList] where all validations are done but dbname 
--									Changed While loop for a cursor 
--				28/11/2016	RAG	- Bug: backup type is ignored and only full backups have been taken regardless of the type specified  
--									in DatabaseInformation.backupSchedule 
--				04/01/2018	RAG	- Added columns from [dbo].[DBA_getDatabasesMaintenanceList]
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
--								- Added clause to add COPY_ONLY on secondary databases
--								- Added functionality to put COPY_ONLY backups when @isCopyOnly = 1 in a different folder
-- 
-- Assumptions:	- Databases defined in [DBA].[dbo].[DatabaseInformation] has a backup schedule defined in a Bitwise format which matches  
--					the values of [DBA].[dbo].[DaysOfWeekBitWise] 
--				- Backup Path should be defined either at Instance level in [DBA].[dbo].[InstanceInformation] column [backupRootPath] 
--					or Database level in [DBA].[dbo].[DatabaseInformation] column [backupRootPath].  
--					If it's not defined at DB level will take the path defined at Instance Level. 
--				- In case the backups are taken in "Batches", the batch number should be defined at database level and passed to the SP as parameter 
--				- The number of files for the backup is defined at DB level in [DBA].[dbo].[DatabaseInformation] column [backupNFiles], defaulted to 1 
--					IMPORTANT to change this for big databases! 
-- 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_runDatabaseBackup]  
	@dbname				SYSNAME			= NULL 
	, @isCopyOnly		BIT				= 0		-- SET to 1 to create a backup with COPY_ONLY option 
	, @path				NVARCHAR(512)	= NULL	-- Specific path to backup the database 
	, @deleteOldBackups BIT				= 1		-- to control if old backups are deleted according the settings or not 
	, @BackupType		CHAR(1)			= NULL	-- D -> Full backup, I -> Differential 
	, @batchNo			TINYINT			= NULL  
	, @weekDayOverride	TINYINT			= NULL 
	, @debugging		BIT				= 0		-- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS 
AS 
BEGIN 
 
	SET NOCOUNT ON 
 
	-- Adjust parameters 
	SET @isCopyOnly			= ISNULL(@isCopyOnly, 0) 
	SET @deleteOldBackups	= ISNULL(@deleteOldBackups, 1) 
	SET @path				= ISNULL(@path, '') 
	SET @batchNo			= CASE WHEN @dbname IS NULL THEN @batchNo ELSE NULL END -- Clear @batchNo parameter when specifying a database name		 
	SET @debugging			= ISNULL(@debugging, 0) 
		 
	IF @weekDayOverride NOT BETWEEN 1 AND 7  BEGIN  
		RAISERROR ('The value specified for @weekDayOverride is not valid, please specify a value between 1 (Sunday) and 7 (Saturday)', 16, 0) 
		RETURN -50 
	END  
 
	DECLARE @deleteOldBackupsOverride	BIT				= CASE WHEN @isCopyOnly = 1 OR @BackupType = 'I' THEN 0 ELSE @deleteOldBackups END -- NEVER delete old backups for COPY_ONLY or DIFFERENTIAL backups 
			, @InstaceProductVersion	DECIMAL(3,1)	= ( SELECT [dbo].[getNumericSQLVersion](CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion'))) ) 
			, @InstanceEngineEdition	INT				= ( SELECT CONVERT(INT, SERVERPROPERTY('EngineEdition')) ) 
			, @isPathOverride			BIT				= CASE WHEN @path <> '' THEN 1 ELSE 0 END		 
			, @dayOfTheWeek				INT				= ISNULL(@weekDayOverride, DATEPART(WEEKDAY, GETDATE())) 
 
	DECLARE @db TABLE(database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL, role TINYINT NOT NULL, secondary_role_allow_connections TINYINT NOT NULL) 
 
	DECLARE @backupfiles	TABLE (dbname			SYSNAME NOT NULL 
									, fileID		INT NOT NULL
									, files			INT NOT NULL 
									, fileDiskPath	NVARCHAR(512) NOT NULL) 
 
	DECLARE @nFiles				INT 
			, @options			NVARCHAR(200) 
			, @timetext			VARCHAR(15)		= [DBA].[dbo].[formatTimeToText]()  
			, @fileName			SYSNAME 
			, @fileExtension	SYSNAME 
			, @keepNbackups		TINYINT 
			, @sqlString		NVARCHAR(2000) 
			, @mkdirCmd			NVARCHAR(1000) 
			, @emailCmd			NVARCHAR(1000) 
			, @errorMsg			NVARCHAR(1000)	= N'' 
			, @startTime		DATETIME 
			, @role				TINYINT
 
	 
	IF @path <> '' AND @isCopyOnly = 0 BEGIN 
		SET @errorMsg = N'The parameter @path can be only specified if the parameter @isCopyOnly is set to 1.' 
		RAISERROR ( @errorMsg, 16,1 ) 
		RETURN -100 
	END 
 
	IF @dbname IS NOT NULL AND ISNULL(@BackupType, '') NOT IN ('D', 'I') BEGIN 
		SET @errorMsg = N'The parameter @BackupType accept values ''D'' or ''I'' when @dbname is specified.' 
		RAISERROR ( @errorMsg, 16,1 ) 
		RETURN -110 
	END 
 
	IF @BackupType = 'I' AND @isCopyOnly = 1 BEGIN 
		SET @errorMsg = N'The parameter @BackupType can only accept value ''D'' (Full database backup) when @isCopyOnly is true (1).' 
		RAISERROR ( @errorMsg, 16,1 ) 
		RETURN -120 
	END 
 
	INSERT INTO @db (database_id, database_name, role, secondary_role_allow_connections)
		EXECUTE [dbo].[DBA_getDatabasesMaintenanceList]
 
	DECLARE dbs CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
		SELECT db.[database_name] COLLATE DATABASE_DEFAULT 
					, CASE WHEN @isPathOverride = 1 THEN @path 
						ELSE 
							CASE WHEN @isCopyOnly = 1 THEN [DBA].dbo.getBackupRootPath(@@SERVERNAME, db.database_name) + 'COPY_ONLY\' 
							ELSE [DBA].dbo.getBackupRootPath(@@SERVERNAME, db.database_name) 
						END
					END 
					, ISNULL(D.backupNFiles, 1) 
					, ISNULL(D.keepNbackups, I.keepNbackups) 
					, CASE WHEN @isCopyOnly = 1 THEN 'D' ELSE ISNULL(@BackupType, SUBSTRING(D.backupSchedule, @dayOfTheWeek, 1)) END  
					--copy only backups always full database, @BackupType takes precedence if specified 
					, db.role
			FROM @db AS db 
				INNER JOIN [DBA].[dbo].[DatabaseInformation] AS D 
					ON d.database_id = db.database_id 
						AND d.server_name = @@SERVERNAME 
				INNER JOIN [DBA].[dbo].ServerConfigurations AS I   
					ON I.server_name = D.server_name 
			WHERE  
					(( SUBSTRING(D.backupSchedule, @dayOfTheWeek, 1) IN ('D', 'I') OR @isCopyOnly = 1 )-- New Schedule Checker 
						AND ISNULL(D.backupBatchNo, 0) = ISNULL(@batchNo, 0) 
						AND @dbname IS NULL  
					) 
				OR db.database_name = @dbname 
		ORDER BY db.[database_name] 
  
	OPEN dbs 
	FETCH NEXT FROM dbs INTO @dbname, @path, @nFiles, @keepNbackups, @BackupType, @role
 
	WHILE @@FETCH_STATUS = 0 BEGIN 
 
		-- This souldn't happen as the function dbo.getBackupRootPath will take instance defaults, but keep it jic 
		IF @path = '' BEGIN 
			PRINT 'Cannot backup database ' + QUOTENAME(@dbname) + ' because there is no backup path defined.' 
			FETCH NEXT FROM dbs INTO @dbname, @path, @nFiles, @keepNbackups, @BackupType, @role
			CONTINUE 
		END 
 
		-- Define different options, here we can have a mix of full and diffs, so calculate for each 
		SET @options = ' WITH NOINIT, CHECKSUM' +  
						-- Add compression keyword for SQL2008-Enterprise or 2008R2/2012 -Enterprise & Standard Editions 
							CASE  
								WHEN   ( @InstaceProductVersion = 10.0	AND @InstanceEngineEdition = 3 ) 
									OR ( @InstaceProductVersion > 10.0	AND @InstanceEngineEdition IN (2,3) ) 
								THEN ', COMPRESSION' 
								ELSE ''							 
							END +  
							CASE  
								WHEN @isCopyOnly = 1 OR @role = 2 THEN ', COPY_ONLY'  -- Specified or secondaries
								ELSE ''  
							END +  
							CASE  
								WHEN @BackupType = 'I' THEN ', DIFFERENTIAL'  
								ELSE '' 
							END 
 
		SET @deleteOldBackups	= CASE WHEN @isCopyOnly = 1 OR @BackupType = 'I' THEN 0 ELSE ISNULL(@deleteOldBackupsOverride, 0) END -- NEVER delete old backups for COPY_ONLY or DIFFERENTIAL backups 
 
		DELETE @backupfiles	 
	 
		-- Create folder if does not exist 
		SET @mkdirCmd = 'EXEC master..xp_cmdshell ''if not exist "' + @path + '". md "' + @path + '".''' 
 
		SET @fileName		= @dbname + '_' + @timetext 
		SET @fileExtension	=	CASE  
									WHEN @BackupType = 'I' THEN '.diff'''   
									WHEN @BackupType = 'D' AND (@isCopyOnly = 1 OR @role = 2) THEN '.COPY_ONLY.bak'''  
									ELSE '.bak'''  
								END 
	 
		-- Generate Device: Filenames for backups 
		;WITH CTE_Files AS ( 
			SELECT @dbname AS dbname 
					, 1 AS FileId 
					, @nFiles AS nFiles 
					, 'DISK = ''' + @path + @fileName + CASE WHEN @nFiles > 1 THEN '_' + RIGHT('00' + CAST(1  AS NVARCHAR(10)),2) ELSE '' END + @fileExtension AS diskpath 
					--, dbname + '_' + @timetext + CASE WHEN nFiles > 1 THEN '_' + RIGHT('00' + CAST(1  AS NVARCHAR(10)),2) ELSE '' END + CASE WHEN @isCopyOnly = 1 THEN '.bak.COPY_ONLY' ELSE '.bak' END  AS fileName 
			UNION ALL 
			SELECT @dbname 
					, FileId + 1 
					, @nFiles 
					, 'DISK = ''' + @path + @fileName + '_' + RIGHT('00' + CAST(FileId + 1 AS NVARCHAR(10)),2) + @fileExtension 
					--, dbname + '_' + @timetext + '_' + RIGHT('00' + CAST(FileId + 1 AS NVARCHAR(10)),2) + CASE WHEN @isCopyOnly = 1 THEN '.bak.COPY_ONLY' ELSE '.bak' END 
				FROM CTE_Files 
				WHERE FileId < @nFiles 
					AND @nFiles > 1 
		) 
	 
		INSERT INTO @backupfiles 
			SELECT * FROM CTE_Files 
 
		-- Generate backup statements  
		SELECT @sqlString = 'BACKUP DATABASE ' +  QUOTENAME(@dbname) + CHAR(10) + ' TO ' + z.DiskPath2
			FROM (	 
				SELECT DISTINCT f.dbname, D.DiskPath2
					FROM @backupfiles f 
						CROSS APPLY ( SELECT STUFF(  
											(SELECT ', '+ fileDiskPath + CHAR(10) 
												FROM @backupfiles f2 
												WHERE f2.dbname = f.dbname 
												ORDER BY fileDiskPath 
												FOR XML PATH(''), TYPE).value('.', 'varchar(max)') 
											,1,2,'') 
						)  D ( DiskPath2 ) 
			) z 
	 
		SET @sqlString = @sqlString + @options + '' 
 
		BEGIN TRY 
		 
			PRINT @mkdirCmd 
			PRINT @sqlString					 
			 
			SET @startTime = GETDATE() 
 
			IF @debugging = 0 BEGIN 	 
				EXEC sp_executesql @stmt = @mkdirCmd 
				EXEC sp_executesql @stmt = @sqlString 
			END 
 
			PRINT CHAR(10) + '/*****************************************' 
			PRINT 'Backup Total Time for DB ' + QUOTENAME(@dbname) + ' : ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startTime, GETDATE()) ) 
			PRINT '*****************************************/' 
		 
			IF @deleteOldBackups = 1 BEGIN  
				PRINT CHAR(10) + 'Calling [dbo].[DBA_deleteOldBackups], @keepNbackups: ' + CONVERT(VARCHAR(2), @keepNbackups) 
				EXECUTE [DBA].[dbo].[DBA_deleteOldBackups]  
						@instanceName		= @@SERVERNAME 
						, @dbname			= @dbname 
						, @keepNbackups		= @keepNbackups 
						, @includeMockFile	= @debugging -- It's the same value as @debugging!! DO NOT CHANGE! 
						, @debugging		= @debugging 
			END 
 
		END TRY		 
		BEGIN CATCH 
			SET @emailCmd = 'EXEC msdb..sp_send_dbmail	 
								@profile_name = ''Admin Profile'',  
								@recipients = ''DatabaseAdministrators@rws.com'',  
								@subject = ''Database Backup Failed'',  
								@body = ''' + @@SERVERNAME + ', ' + @dbname + CHAR(10) + '. The application returned the following error:' + CHAR(10) + 
										ERROR_MESSAGE() + '''' 
 
		 
			EXEC sp_executesql @stmt = @emailCmd 
		END CATCH 
	 
		IF @debugging = 1 BEGIN 	 
			PRINT @emailCmd 
		END 
	 
		FETCH NEXT FROM dbs INTO @dbname, @path, @nFiles, @keepNbackups, @BackupType, @role
 
	END 
 
	CLOSE dbs 
	DEALLOCATE dbs 
 
END 


GO
