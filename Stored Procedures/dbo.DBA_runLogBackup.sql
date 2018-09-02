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
-- Create date: 25/03/2013 
-- Description:	Backups the transaction log for a given database if needed 
--				 
-- Change Log:	 
--				10/09/2013	RAG - Included message if the Database is not in Full Recovery Model 
--				22/10/2013	RAG - Included ERROR_MESSAGE in the body of the email in case the backup fails 
--				22/10/2013	RAG - Change the value of @timeText to use the new function [DBA].[dbo].[formatTimeToText]() which will be used  
--									from now on for backups (full & trn) 
--				22/10/2013	RAG - The value of @timeText will be calculated once at the begining of the process, this way  
--									all backups taken in the same run will have the same date suffix 
--				22/10/2013	RAG - Added check to add options according the SQL Server version running the SP 
--				22/10/2013	RAG - Removed WITH CHEKSUM when COMPRESSION is on as that is the default behaviour 
--									http://technet.microsoft.com/en-us/library/ms186865(v=sql.105).aspx 
--				24/10/2013	RAG - Excluded read only databases from the process 
--				17/03/2014	RAG - Added functionality to run FULL backup if there's no one. 
--				28/10/2015	RAG - Changed INIT to NOINIT, http://www.sqldoubleg.com/2015/10/28/daylight-savings-end-affects-not-only-you-but-your-sql-server-too/ 
--				11/07/2016	RAG - Changed the call to do Full backup to new SP [DBA_runDatabaseBackup]  
--				18/07/2016	RAG - Added validation for PRIMARY replicas in case there are Availability Groups configured, only for scheduled backups 
--				14/09/2016	RAG	-  
--									Removed validation for PRIMARY replicas. 
--									Databases are now coming from [dbo].[DBA_getDatabasesMaintenanceList] where all validations are done but dbname 
--									Changed While loop for a cursor 
--				04/01/2018	RAG	- Added columns from [dbo].[DBA_getDatabasesMaintenanceList]
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
--								- Log Backups will look now also to [dbo].[DatabaseInformation].[BackupSchedule] 
--									to see if the database is meant to be backed up or not
--
--	To do: 
--				Find the way of detecting if the recovery model has changed from simple to full as backups will exists but a new one is needed 
--				 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_runLogBackup] 
	@dbname					SYSNAME = NULL 
	, @skipUsageValidation	BIT		= 0 -- Used to do the backup no matter if it's required due to log usage 
	, @debugging			BIT		= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS 
AS 
BEGIN 
	 
	SET NOCOUNT ON 
	 
	SET @skipUsageValidation	= ISNULL(@skipUsageValidation, 0) 
	SET @debugging				= ISNULL(@debugging, 0) 
 
	DECLARE @time			DATETIME = GETDATE() 
			, @totalTime	DATETIME = GETDATE() 
 
	DECLARE @db TABLE(database_id INT NOT NULL PRIMARY KEY, name SYSNAME NOT NULL, role TINYINT, secondary_role_allow_connections TINYINT)
	 
	DECLARE @InstaceProductVersion		DECIMAL(3,1)	= ( SELECT [dbo].[getNumericSQLVersion](CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion'))) ) 
			, @InstanceEngineEdition	INT				= ( SELECT CONVERT(INT, SERVERPROPERTY('EngineEdition')) ) 
 
	DECLARE @backupPath		NVARCHAR(512) 
			, @options		NVARCHAR(200)	 
			, @timetext		VARCHAR(15)		= [DBA].[dbo].[formatTimeToText]() 
			, @sqlString	NVARCHAR(1000) 
			, @dirCmd		NVARCHAR(1000) 
			, @emailCmd		NVARCHAR(2000) 
			, @ErrorMsg		NVARCHAR(MAX) 
 
	SET @options = ' WITH NOINIT' +  
						CASE  
							WHEN   ( @InstaceProductVersion = 10.0	AND @InstanceEngineEdition = 3 ) 
								OR ( @InstaceProductVersion > 10.0	AND @InstanceEngineEdition IN (2,3) ) 
							THEN ', COMPRESSION'							 
						END + ', CHECKSUM'  
			 
	DECLARE @isProduction		BIT		= ( SELECT isProduction FROM DBA.dbo.ServerList WHERE server_name = @@SERVERNAME ) 
	 
	DECLARE @dbCurLogSize		FLOAT 
			, @dbCurLogUsage	FLOAT 
			, @dbMaxLogSize		FLOAT	= CASE WHEN @isProduction = 0 THEN 1024 ELSE 20480 END	-- 1gb for DEV, if not 20gb  
			, @dbMaxLogUsage	FLOAT	= CASE WHEN @isProduction = 0 THEN 10.0 ELSE 25.0  END	-- 10% for DEV, if not 25% usage (5gb) 
 
	DECLARE @sqlperf TABLE ( 
			databaseName	SYSNAME NULL
			, logSize		FLOAT 	NULL
			, logSpaceUsed	FLOAT 	NULL
			, [status]		BIT		NULL) 
 
	INSERT INTO @db (database_id, name, role, secondary_role_allow_connections) 
		EXECUTE [dbo].[DBA_getDatabasesMaintenanceList]
 
	DECLARE dbs CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
		SELECT db.name 
				, [DBA].[dbo].[getBackupRootPath] ( @@SERVERNAME, db.name ) 
			FROM @db AS db 
				INNER JOIN sys.databases AS d 
					ON d.database_id = db.database_id 
				INNER JOIN [DBA].[dbo].[DatabaseInformation] AS di
					ON di.database_id = db.database_id 
						AND di.server_name = @@SERVERNAME 
						AND di.BackupSchedule <> N'-------'
			WHERE db.name NOT LIKE '%_checkDB' -- Just in case there's a restored db for checkDB 
				AND db.name = ISNULL(@dbname, db.name) 
				AND ( d.recovery_model IN (1, 2) OR @debugging = 1 ) -- Full or Bulk Logged when no debugging 
			ORDER BY db.name 
			 
	OPEN dbs 
	FETCH NEXT FROM dbs INTO @dbname, @backupPath 
 
	WHILE @@FETCH_STATUS = 0 BEGIN 
 
		IF @skipUsageValidation = 0 BEGIN  
			-- Get log information  
			INSERT INTO @sqlperf (databaseName, logSize, logSpaceUsed, [status])  
			EXEC ('DBCC SQLPERF (LOGSPACE) WITH NO_INFOMSGS') 
		END  
 
		-- This cannot happen as the function above will return Default Instance Backup Path if not defined in DBA database, but leave it jic 
		IF ISNULL(@backupPath, '') = '' BEGIN 
			SET @ErrorMsg = N'There is no backup path defined for database ' + QUOTENAME(@dbname) + ' in server ' + QUOTENAME(@@SERVERNAME) 
			RAISERROR ( @ErrorMsg, 16,1 ) 
			RETURN -100	 
		END 
	 
		-- If there's no FULL BACKUP, run one 
		IF NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset AS b WHERE b.database_name = @dbname and type = 'D') BEGIN				 
			EXECUTE [dbo].[DBA_runDatabaseBackup]  
					@dbname				= @dbname 
					,@isCopyOnly		= 0 
					,@path				= NULL 
					,@deleteOldBackups	= 1 
					,@BackupType		= N'D' 
					,@batchNo			= NULL 
					,@weekDayOverride	= NULL 
					,@debugging			= @debugging 
 
		END  
 
		IF @skipUsageValidation = 0 BEGIN  
			SELECT @dbCurLogSize		= logSize 
					, @dbCurLogUsage	= logSpaceUsed 
				FROM @sqlperf  
				WHERE databaseName = @dbname 
		END  
			 
		SET @dirCmd		= 'EXEC master..xp_cmdshell ''if not exist "' + @backupPath + '". md "' + @backupPath + '".''' 
		SET @sqlString	= 'BACKUP LOG ' +  QUOTENAME(@dbname) + ' TO DISK = ''' + @backupPath + @dbname + '_' + @timetext + '.trn'' ' + @options + '' 
		 
		PRINT @dirCmd 
		PRINT @sqlString 
 
		BEGIN TRY		 
			IF @dbCurLogSize > @dbMaxLogSize OR @dbCurLogUsage > @dbMaxLogUsage OR @skipUsageValidation = 1 BEGIN 
				SET @time = GETDATE() 
				IF @debugging = 0 BEGIN 
					EXEC sp_executesql @stmt = @dirCmd 
					EXEC sp_executesql @stmt = @sqlString 
				END					 
				PRINT 'Time taken: ' + [dbo].[formatSecondsToHR](DATEDIFF(SECOND, @time, GETDATE())) + CHAR(10)  
			END  
			ELSE BEGIN 
				PRINT N'No need to backup the tranlog for database : ' + QUOTENAME(@dbname) + ' Log size: ' + STR(@dbCurLogSize) + 'MB, Used:' + STR(@dbCurLogUsage) + '%' + CHAR(10) 
			END			 
		END TRY		 
		BEGIN CATCH 
				 
			SET @ErrorMsg= REPLACE(ERROR_MESSAGE(), '''', '''''') -- Errors usually come with something in quotes, escape them to concat it to the sql string  
				 
			SET @emailCmd = 'EXEC msdb..sp_send_dbmail	 
								@profile_name = ''Admin Profile'',  
								@recipients = ''DatabaseAdministrators@rws.com'',  
								@subject = ''Log Backup Failed'',  
								@body = ''' + @@SERVERNAME + ', ' + @dbname + CHAR(10) + 'The application returned the following error:' + CHAR(10) +  
										@ErrorMsg + '''' 
				 
			PRINT @emailCmd 
			EXEC sp_executesql @stmt = @emailCmd 
		END CATCH 
 
		FETCH NEXT FROM dbs INTO @dbname, @backupPath 
 
	END 
 
	CLOSE dbs 
	DEALLOCATE dbs 
 
	PRINT CHAR(10) + 'Total Time taken: ' + [dbo].[formatSecondsToHR](DATEDIFF(SS, @totalTime, GETDATE())) + CHAR(10)  
 
END 
GO
