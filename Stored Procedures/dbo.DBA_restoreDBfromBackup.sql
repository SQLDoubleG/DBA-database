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
-- Create date: 15/07/2013
-- Description:	Restore Databases from Backup Files
--
-- Parameters:	- @SourceInstanceName	-> Instance from where we want to restore the backup, MANDATORY
--				- @SourceDBName			-> Name of the source DB we want to restore, MANDATORY
--				- @TargetDBName			-> OPTIONAL. Name of the destination DB, if not provided it will be the same as @SourceDBName
--				- @SourceFileName		-> File name of the backup we want to restore. It can be either a full or a tran log backup
--				- @RestoreLastBackup	-> Will restore last full backup for the SourceInstanceName.@SourceDBName. Only if @SourceFileName IS NULL
--				- @SourceFilePath		-> Folder where the backup file is located. It's recommended to use NETWORK PATHS to avoid confusion (eg '\\SERVERNAME\sharedFolder\')
--				- @NewDataFilePath 		-> OPTIONAL. Name of the folder we want to place the DB DATA files
--				- @NewLogFilePath		-> OPTIONAL. Name of the folder we want to place the DB LOG files
--				- @WithReplace			-> OPTIONAL. Will add WITH REPLACE to the restore statement
--				- @WithRecovery			-> OPTIONAL. Will generate an extra RESTORE DATABASE WITH RECOVERY statement, otherwise restore will no recover the database
--				- @WithStats			-> OPTIONAL. Will add WITH STATS to the restore statement
--				- @KeepDbOwner			-> OPTIONAL. Will generate an extra ALTER AUTHORIZATION statement change the owner to the original for for @SourceDBName in @SourceInstanceName
--				- @debugging			-> OPTIONAL. Will print out the statements without executing them
--
-- Assumptions:	- Backup Files comply the following format
--					- Full backup	-> dbname_YYYYMMDD[_N].bak
--					- Log backup	-> dbname_YYYYMMDD_HHmmSS.trn
--				- Destination Database can exist or not in the Instance the script is executed 
--					- If the DB exists
--						- Database files (Data+Log) will be placed in the location specified in @NewDataFilePath/@NewLogFilePath, if not will be in the CURRENT LOCATION
--						- Before executing the restore statement, the DB will be set to SINGLE_USER WITH ROLLBACK IMMEDIATE
--						- After executing all the restore statements, the DB will be set back to MULTI_USER 
--					- If the DB doesn't exist
--						- Database files (Data+Log) will be placed in the location specified in @NewDataFilePath/@NewLogFilePath, if not will be in the SERVER DEFAULT 
--
-- Log History:	- 15/08/2013 - RAG - Added some tweaks for master database, which cannot be restored as others.
--				- 09/01/2016 - RAG - Added New columns in SQL 2016 from RESTORE FILELISTONLY command
--				- 13/01/2014 - RAG - Added command to enable broker if required
--				- 23/03/2016 - RAG - Added command to change database owner to the original one for @SourceDBName in @SourceInstanceName
--				- 08/06/2016 - RAG - Added validation for backup root path 
--				- 14/07/2016 - SZO - Added catch for condition where Restore statement is greater than 4,000 characters.
--				- 20/07/2016 - RAG - Removed catch for condition where Restore statement is greater than 4,000 characters.
--									- Added logic to restore LOG with RESTORE LOG instead of RESTORE DATABASE, and removed WITH STOPAT from full and diff restores
--									- Fixed a bug for multi files differential backups
--									- Split the main command in different commands which are executed independently according to the parameters
--				- 16/10/2017 - RAG	- Added validation for database existance before setting to single user.
--									- Return one single statement in XML format when debugging, this is useful to copy/paste
--									- Added commands to create the Data and Log files folder if they do not exist
--				- 31/10/2017 - RAG	- Moved the logic to determine the data and log files path, so follows this rule
--										- If we have passed data and log files location, we use those. Path will be created as needed
--										- If the database exists, we keep the current location
--										- Finally if nothing from above apply, we use instance default paths
--				- 26/03/2017 - RAG	- Added a backslash at the end of the following paths in case they don't have it
--										- @DataFilePath
--										- @LogFilePath
--										- @BackupRootPath
--				- 05/04/2017 - RAG	- Moved @SetMultiUser, @SetEnableBroker	and @ChangeDbOwner to be added if @WithRecovery = 1, otherwise makes no sense
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_restoreDBfromBackup]
	@SourceInstanceName		SYSNAME
	, @SourceDBName			SYSNAME
	, @TargetDBName			SYSNAME			= NULL
	, @SourceFileName		SYSNAME			= NULL
	, @RestoreLastBackup	BIT				= NULL
	, @SourceFilePath		SYSNAME			= NULL
	, @NewDataFilePath		NVARCHAR(255)	= NULL
	, @NewLogFilePath		NVARCHAR(255)	= NULL
	, @WithStopAt			DATETIME		= NULL
	, @WithReplace			BIT				= NULL
	, @WithRecovery			BIT				= NULL
	, @WithStats			BIT				= NULL
	, @KeepDbOwner			BIT				= NULL
	, @debugging			BIT				= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
	
AS
BEGIN
	
	SET NOCOUNT ON
	SET QUOTED_IDENTIFIER ON

	-- Set the targetDB before setting the vbles
	SET @SourceInstanceName	= ISNULL(@SourceInstanceName, '')
	SET @SourceDBName		= ISNULL(@SourceDBName, '')
	SET @TargetDBName		= CASE WHEN @TargetDBName IS NOT NULL THEN @TargetDBName ELSE @SourceDBName END
	SET @RestoreLastBackup	= ISNULL(@RestoreLastBackup, 0)
	SET @SourceFilePath		= ISNULL(CASE WHEN RIGHT(@SourceFilePath, 1) = '\' THEN @SourceFilePath ELSE @SourceFilePath + '\' END, '')
	SET @SourceFileName		= ISNULL(@SourceFileName, '')
	SET @WithReplace		= ISNULL(@WithReplace, 0)
	SET @WithStopAt			= ISNULL(@WithStopAt, '')
	SET @WithRecovery		= ISNULL(@WithRecovery, 0)
	SET @KeepDbOwner		= ISNULL(@KeepDbOwner, 0) 
	SET @debugging			= ISNULL(@debugging, 0)

	-- Declare rest of the variables.
	DECLARE	@BackupRootPath						NVARCHAR(256)
			, @CountFiles						INT
			, @MinFileID						INT
			, @MaxFileID						INT
			, @RestoreFileListCommand			NVARCHAR(MAX)	= N'RESTORE FILELISTONLY FROM'
			, @RestoreDatabaseCommand			NVARCHAR(MAX)	= N'RESTORE DATABASE ' + QUOTENAME(@TargetDBName) + CHAR(10) + CHAR(9) + N'FROM '
			, @RestoreDBWithRecovery			NVARCHAR(MAX)	= N'RESTORE DATABASE ' + QUOTENAME(@TargetDBName) + N' WITH RECOVERY'
			, @RestoreFileMoveCommand			NVARCHAR(MAX)	= N'' 
			, @RestoreWithStopAt				NVARCHAR(MAX)	= CASE WHEN @WithStopAt <> ''	THEN CHAR(10) + CHAR(9) + CHAR(9) + ', STOPAT = ''' + CONVERT(VARCHAR(25),@WithStopAt) + ''''	ELSE '' END
			, @RestoreWithReplace				NVARCHAR(MAX)	= CASE WHEN @WithReplace = 1	THEN ', REPLACE' ELSE '' END
			, @RestoreWithStats					NVARCHAR(MAX)	= CASE WHEN @WithStats = 1		THEN ', STATS' ELSE '' END	
			, @DataFilePath						NVARCHAR(255)	= NULL
			, @LogFilePath						NVARCHAR(255)	= NULL
			, @CreateDataFilePathCommand		NVARCHAR(MAX)	= NULL
			, @CreateLogFilePathCommand			NVARCHAR(MAX)	= NULL
			, @existDBinServer					BIT				= ISNULL( DB_ID(@TargetDBName), 0 )
			, @ErrorMsg							NVARCHAR(1000)	= N''
			, @StartTime						DATETIME		= GETDATE()
			, @FilePath							NVARCHAR(256)

	DECLARE @BackupType							SMALLINT
			, @BackupDatabaseName				NVARCHAR(128)		
			, @IsCopyOnly						BIT
			, @MediaSetId						UNIQUEIDENTIFIER
			, @FamilyCount						INT
			, @FamilySequenceNumber				INT
			, @Order							NVARCHAR(5)


	DECLARE	@SetSingleUser						NVARCHAR(1000)	= N'USE [master]' + CHAR(10) + N'' + CHAR(10) + 
																	N'IF ( DB_ID(''' + @TargetDBName + N''') ) IS NOT NULL ALTER DATABASE ' + QUOTENAME(@TargetDBName) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
			, @SetMultiUser						NVARCHAR(1000)	= N'USE [master]' + CHAR(10) + N'' + CHAR(10) + 
																	N'ALTER DATABASE ' + QUOTENAME(@TargetDBName) + N' SET MULTI_USER WITH ROLLBACK IMMEDIATE'
			, @SetEnableBroker					NVARCHAR(1000)	=	ISNULL((SELECT N'ALTER DATABASE ' + QUOTENAME(name) + N' SET NEW_BROKER WITH ROLLBACK IMMEDIATE'
																				FROM DBA.dbo.DatabaseInformation 
																				WHERE name = @TargetDBName 
																					AND server_name = @SourceInstanceName
																					AND is_broker_enabled = 1), '')
			, @ChangeDbOwner					NVARCHAR(1000)	= N'USE [master]' + CHAR(10) + N'' + CHAR(10) + 
																	N'ALTER AUTHORIZATION ON DATABASE::' + QUOTENAME(@TargetDBName) + N' TO ' + 
																	(SELECT QUOTENAME(owner_name) FROM DBA.dbo.DatabaseInformation WHERE server_name = @SourceInstanceName AND name = @SourceDBName)
																		
	DECLARE @BACKUPTYPE_DATABASE				SMALLINT = 1
	DECLARE @BACKUPTYPE_TRANSACTION_LOG			SMALLINT = 2
	DECLARE @BACKUPTYPE_FILE					SMALLINT = 4
	DECLARE @BACKUPTYPE_DIFFERENTIAL_DATABASE	SMALLINT = 5
	DECLARE @BACKUPTYPE_DIFFERENTIAL_FILE		SMALLINT = 6	
	DECLARE @BACKUPTYPE_PARTIAL					SMALLINT = 7
	DECLARE @BACKUPTYPE_DIFFERENTIAL_PARTIAL	SMALLINT = 8	
	
	DECLARE @SQLServerNumericVersion	INT = DBA.dbo.getNumericSQLVersion(NULL)
	
	IF OBJECT_ID('tempdb..#BackupFileList')		IS NOT NULL DROP TABLE #BackupFileList
	IF OBJECT_ID('tempdb..#BackupFileListOnly')	IS NOT NULL DROP TABLE #BackupFileListOnly
	
		-- Store file lists from dir command.
	CREATE TABLE #BackupFileList
			(ID						INT IDENTITY
			, [FileName]			NVARCHAR(256)
			, DatabaseName			NVARCHAR(128)		NULL
			, MediaSetId			UNIQUEIDENTIFIER	NULL
			, BackupType			SMALLINT			NULL
			, FamilyCount			INT					NULL
			, FamilySequenceNumber	INT					NULL
			, IsCopyOnly			BIT					NULL)

	-- Stores results from RESTORE FILELISTONLY
	CREATE TABLE #BackupFileListOnly 
			( LogicalName			NVARCHAR(128)
			, PhysicalName			NVARCHAR(260)
			, [Type]				CHAR(1)
			, FileGroupName			NVARCHAR(128)
			, Size					NUMERIC(20,0)
			, MaxSize				NUMERIC(20,0)
			, FileID				BIGINT
			, CreateLSN				NUMERIC(25,0)
			, DropLSN				NUMERIC(25,0)		NULL
			, UniqueID				UNIQUEIDENTIFIER
			, ReadOnlyLSN			NUMERIC(25,0)		NULL
			, ReadWriteLSN			NUMERIC(25,0)		NULL
			, BackupSizeInBytes		BIGINT
			, SourceBlockSize		INT
			, FileGroupID			INT
			, LogGroupGUID			UNIQUEIDENTIFIER	NULL
			, DifferentialBaseLSN	NUMERIC(25,0)		NULL
			, DifferentialBaseGUID	UNIQUEIDENTIFIER
			, IsReadOnly			BIT
			, IsPresent				BIT
			, TDEThumbprint			VARBINARY(32))


	IF @SQLServerNumericVersion >= 13 BEGIN
		ALTER TABLE #BackupFileListOnly ADD SnapshotURL nvarchar(360) NULL	-- NEW FOR SQL2016 onwards
 	END 

	--============================================================================================
	-- Initial Checks to see if the parameters are correct
	--============================================================================================

	IF ( @SourceDBName = '' ) BEGIN 
		SET @ErrorMsg = N'Please specify a value for parameter @SourceDBName'
		RAISERROR ( @ErrorMsg, 16,1 )
		RETURN -100
	END

	IF ( @SourceInstanceName = '' ) AND ( @SourceFilePath = '' OR @SourceFileName = '' ) BEGIN 
		SET @ErrorMsg = N'Please specify either parameters @SourceInstanceName and @SourceDBName OR @SourceFilePath and @SourceFileName'
		RAISERROR ( @ErrorMsg, 16,1 )
		RETURN -150
	END

	IF @SourceFileName = '' AND @RestoreLastBackup = 0 BEGIN
		SET @ErrorMsg = N'No file name was specified. If the expected result is to restore the last Full backup available, please set the parameter @RestoreLastBackup = 1.'
		RAISERROR ( @ErrorMsg, 16,1 )
		RETURN -200
	END

	IF @SourceFileName <> '' AND @RestoreLastBackup = 1 BEGIN
		SET @ErrorMsg = N'A value was specified for the parameter @SourceFileName together with the parameter @RestoreLastBackup set to 1.' + CHAR(10) +
						N'Please specify a NULL value for @SourceFileName if the intention is to restore the last full backup.'
		RAISERROR ( @ErrorMsg, 16,1 )
		RETURN -300
	END

	-- Always print statements for master database 
	IF @TargetDBName = 'master' BEGIN
		SET @debugging		= 1 
		SET @WithReplace	= 1 
	END

	SELECT @DataFilePath	= COALESCE(@NewDataFilePath, mdf.DatabaseDataPath, DF.[DefaultFile])
			, @LogFilePath	= COALESCE(@NewLogFilePath, ldf.DatabaseLogPath, DF.[DefaultLog])
		FROM DBA.dbo.getInstanceDefaultPaths(@@SERVERNAME) AS DF
		OUTER APPLY (SELECT DBA.dbo.getFilePathFromFullPath(physical_name) AS DatabaseDataPath 
						FROM sys.master_files 
						WHERE database_id = DB_ID(@TargetDBName) AND file_id = 1) AS mdf -- mdf file
		OUTER APPLY (SELECT DBA.dbo.getFilePathFromFullPath(physical_name) AS DatabaseLogPath 
						FROM sys.master_files 
						WHERE database_id = DB_ID(@TargetDBName) AND file_id = 2) AS ldf -- ldf file

	SET @BackupRootPath =	CASE 
								WHEN ISNULL(@SourceFilePath, '') <> '' THEN @SourceFilePath
								ELSE [DBA].dbo.getBackupRootPath(@SourceInstanceName, @SourceDBName)
							END

	IF ISNULL(@BackupRootPath, '') = '' BEGIN
		SET @ErrorMsg = N'There is no path defined for backups for this Server and database combination.' + CHAR(10) +
						N'Please verify @SourceInstanceName and @SourceDBName to be correct.'
		RAISERROR ( @ErrorMsg, 16,1 )
		RETURN -400
	END 

	SET @DataFilePath	+= CASE WHEN RIGHT(@DataFilePath, 1)	<> '\' THEN '\' ELSE '' END
	SET @LogFilePath	+= CASE WHEN RIGHT(@LogFilePath, 1)		<> '\' THEN '\' ELSE '' END
	SET @BackupRootPath	+= CASE WHEN RIGHT(@BackupRootPath, 1)	<> '\' THEN '\' ELSE '' END

	--SELECT @DataFilePath, @LogFilePath, @BackupRootPath

	IF @existDBinServer = 1 AND @WithReplace = 0 BEGIN
		-- Backup the tail of the log if we want to restore database without replacing the current
		BEGIN TRY
			EXECUTE [DBA].[dbo].[DBA_runLogBackup] 
					@dbname					= @TargetDBName	
					, @skipUsageValidation	= 1
					, @debugging			= @debugging
		END TRY
		BEGIN CATCH
			SET @ErrorMsg = N'*************************************************************************' + CHAR(10) +
							N'The tail of the log has not been backed up.' + CHAR(10) +
							N'The process will continue is debugging mode.' + CHAR(10) +
							N'Please check previous errors and fix them or run the statements manually.'  + CHAR(10) + CHAR(10) +
							N'The SP ' + ERROR_PROCEDURE() + ' returned the following message:' + CHAR(10) + CHAR(10) + ERROR_MESSAGE() + CHAR(10) +
							N'*************************************************************************'  + CHAR(10)
			PRINT @ErrorMsg
			SET @debugging = 1
		END CATCH
	END

	PRINT '--Starting Process to Restore Database ' + QUOTENAME(@TargetDBName) + ' In Server ' + QUOTENAME(@@SERVERNAME) + ' @ ' + CONVERT(VARCHAR, @StartTime, 120)
	
	--============================================================================================
	--	Get Information about the file we want to restore
	--============================================================================================
	IF @RestoreLastBackup = 1 BEGIN
		SELECT @BackupType				= @BACKUPTYPE_DATABASE				
	END
	ELSE BEGIN	
		SET @FilePath = @BackupRootPath + @SourceFileName

		EXECUTE [dbo].[DBA_getBackupFileInformation] 
				@FilePath				= @FilePath
				, @BackupType			= @BackupType			OUTPUT
				, @BackupDatabaseName	= @BackupDatabaseName	OUTPUT
				, @IsCopyOnly			= @IsCopyOnly			OUTPUT
				, @MediaSetId			= @MediaSetId			OUTPUT
				, @FamilyCount			= @FamilyCount			OUTPUT
				, @FamilySequenceNumber	= @FamilySequenceNumber	OUTPUT

		IF @BackupDatabaseName <> @SourceDBName BEGIN
			SET @ErrorMsg = N'The file specified does not belong to the source database specified but to ' + QUOTENAME(@BackupDatabaseName) + CHAR(10) +
							N'Please specify a correct database name or choose another file.'
			RAISERROR ( @ErrorMsg, 16, 1 ) 
			RETURN -500
		END
	END

	--SET @Order = CASE WHEN @BackupType = @BACKUPTYPE_DATABASE AND @RestoreLastBackup = 0 THEN 'ASC' ELSE 'DESC' END
	SET @Order = 'DESC'

	-- Get Backup files, @Order DESC for LAST full backup, trn, or diff. ASC for any other full backup
	INSERT INTO #BackupFileList ([FileName])
		EXEC [DBA].[dbo].[DBA_getBackupFilesList] @path = @BackupRootPath, @order = @Order

	-- Remove subsequent files (clause is opposite as the list is sorted in descending order)
	-- and previous if we want to restore a full backup only
	
	--SELECT @FilePath				
	--	   , @BackupType			
	--	   , @BackupDatabaseName	
	--	   , @IsCopyOnly			
	--	   , @MediaSetId			
	--	   , @FamilyCount			
	--	   , @FamilySequenceNumber

	--SELECT * FROM #BackupFileList
	
	DELETE #BackupFileList
		WHERE @RestoreLastBackup = 0
			AND (ID < ( SELECT ID FROM #BackupFileList WHERE FileName = @SourceFileName ) - ( @FamilyCount - @FamilySequenceNumber ) 
				OR ( @BackupType = @BACKUPTYPE_DATABASE AND ID >= ( SELECT ID FROM #BackupFileList WHERE FileName = @SourceFileName ) + ( @FamilySequenceNumber ) ))

	--SELECT * FROM #BackupFileList

	SELECT	@CountFiles = MIN(ID) 
			, @MinFileID = MIN(ID) 
			, @MaxFileID = MAX(ID) 
		FROM #BackupFileList
	
	-- Get header and label information from the backup files we have read
	WHILE @CountFiles <= @MaxFileID BEGIN
			
		SELECT @FilePath = @BackupRootPath + b.FileName
			FROM #BackupFileList AS b 
			WHERE ID = @CountFiles
			
		IF @@ROWCOUNT = 0 BEGIN	
			SET @CountFiles += 1 
			CONTINUE
		END

		EXECUTE [dbo].[DBA_getBackupFileInformation] 
				@FilePath				= @FilePath
				, @BackupType			= @BackupType			OUTPUT
				, @BackupDatabaseName	= @BackupDatabaseName	OUTPUT
				, @IsCopyOnly			= @IsCopyOnly			OUTPUT
				, @MediaSetId			= @MediaSetId			OUTPUT
				, @FamilyCount			= @FamilyCount			OUTPUT
				, @FamilySequenceNumber	= @FamilySequenceNumber	OUTPUT

		IF @BackupDatabaseName <> @SourceDBName BEGIN
			SET @ErrorMsg = 'The backup file ' + @FilePath + ' does not belong to the database ' + QUOTENAME(@SourceDBName)
			RAISERROR ( @ErrorMsg, 0, 0 , 0 ) WITH NOWAIT
			DELETE #BackupFileList WHERE ID = @CountFiles 
		END
		ELSE BEGIN 

			UPDATE #BackupFileList
				SET BackupType				= @BackupType
					, DatabaseName			= @BackupDatabaseName
					, IsCopyOnly			= @IsCopyOnly
					, MediaSetId			= @MediaSetId
					, FamilyCount			= @FamilyCount
					, FamilySequenceNumber	= @FamilySequenceNumber
				WHERE ID = @CountFiles
		
			IF @BackupType = @BACKUPTYPE_DATABASE AND @IsCopyOnly = 0 BEGIN
				-- Once we find the latest full backup we can ommit the rest
				DELETE #BackupFileList 
					WHERE ID >= @CountFiles + @FamilyCount

			END
		END 

		SET @CountFiles += 1

	END

	-- Remove not required files 
	DELETE #BackupFileList 
		WHERE @RestoreLastBackup = 1 
			AND ( BackupType <> @BACKUPTYPE_DATABASE OR ( BackupType = @BACKUPTYPE_DATABASE AND IsCopyOnly = 1 ) )

	-- Delete files between the latest differential backup and the latest full backup (not copy only), as those won't be restored
	DELETE #BackupFileList
		WHERE ID >= (SELECT MIN(ID) + @FamilyCount FROM #BackupFileList WHERE BackupType = @BACKUPTYPE_DIFFERENTIAL_DATABASE) 
			AND ID < (SELECT MIN(ID) FROM #BackupFileList WHERE BackupType = @BACKUPTYPE_DATABASE AND IsCopyOnly = 0)
	
	--SELECT * FROM #BackupFileList
	
	SET @RestoreFileListCommand = (SELECT TOP 1 @RestoreFileListCommand + ' DISK = ''' + @BackupRootPath + FileName + '''' FROM #BackupFileList)
	
	INSERT INTO #BackupFileListOnly
		EXEC sp_executesql @RestoreFileListCommand 

	SET @CreateDataFilePathCommand = N'EXEC master..xp_cmdshell ''if not exist "' + @DataFilePath + '". md "' + @DataFilePath + '".'''
	SET @CreateLogFilePathCommand = N'EXEC master..xp_cmdshell ''if not exist "' + @LogFilePath + '". md "' + @LogFilePath + '".'''

	SET @RestoreFileMoveCommand = (SELECT CHAR(10) + CHAR(9) + CHAR(9) + ', MOVE ''' + D.LogicalName + ''' TO ''' + 
											CASE WHEN D.[Type] = 'D' THEN @DataFilePath ELSE @LogFilePath END + 
											REPLACE(DBA.dbo.getFileNameFromPath(D.PhysicalName), @SourceDBName, @TargetDBName) + ''''
										FROM #BackupFileListOnly AS D
											LEFT JOIN sys.master_files AS mf
												ON DB_NAME(mf.database_id) = @TargetDBName -- if targetDB exist, we get files from it
													AND mf.name = D.LogicalName COLLATE  Latin1_General_CI_AS
										FOR XML PATH(''))

	SET @RestoreDatabaseCommand = CASE WHEN @existDBinServer = 1 AND @TargetDBName <> 'master'	THEN @SetSingleUser	+ CHAR(10) + '' ELSE '' END 
										+ ( SELECT CHAR(10) + RestoreDatabaseCommand
												FROM (	SELECT DISTINCT
																CASE WHEN b.BackupType = 2 THEN 'RESTORE LOG ' + QUOTENAME(@TargetDBName) + CHAR(10) + CHAR(9) + ' FROM ' + 
																									STUFF((SELECT CHAR(10) + CHAR(9) + CHAR(9) + ', DISK = ''' + @BackupRootPath + b2.FileName + ''''
																												FROM #BackupFileList AS b2
																												WHERE b2.MediaSetId = b.MediaSetId
																												ORDER BY FamilySequenceNumber ASC
																												FOR XML PATH('') ), 1, 4, '') 
																									+ CHAR(10) + CHAR(9) + ' WITH NORECOVERY' + @RestoreWithStopAt
							
																ELSE 'RESTORE DATABASE ' + QUOTENAME(@TargetDBName) + CHAR(10) + CHAR(9) + ' FROM ' + 
																						STUFF((SELECT CHAR(10) + CHAR(9) + CHAR(9) + ', DISK = ''' + @BackupRootPath + b2.FileName + ''''
																									FROM #BackupFileList AS b2
																									WHERE b2.MediaSetId = b.MediaSetId
																									ORDER BY FamilySequenceNumber ASC
																									FOR XML PATH('') ), 1, 4, '') 
																	+ CHAR(10) + CHAR(9) + ' WITH NORECOVERY' + 
																	+ @RestoreWithReplace + @RestoreWithStats + @RestoreFileMoveCommand --+ @RestoreWithStopAt 
																	+ CHAR(10) + ''
																END AS RestoreDatabaseCommand
															FROM #BackupFileList AS b) AS t
												FOR XML PATH('') )
										--+ CASE WHEN @WithRecovery = 1									THEN CHAR(10) +	@RestoreDBWithRecovery 	+ CHAR(10) + 'GO'	ELSE '' END
										--+ CASE WHEN @existDBinServer = 1 AND @TargetDBName <> 'master'	THEN CHAR(10) + @SetMultiUser			+ CHAR(10) + 'GO'	ELSE '' END 
										--+ CASE WHEN @SetEnableBroker <> ''								THEN CHAR(10) + @SetEnableBroker		+ CHAR(10) + 'GO'	ELSE '' END 
										--+ CASE WHEN @KeepDbOwner = 1 AND @ChangeDbOwner IS NOT NULL		THEN CHAR(10) + @ChangeDbOwner			+ CHAR(10) + 'GO'	ELSE '' END;
	
	IF @debugging = 1 BEGIN
		SET @RestoreDatabaseCommand = @CreateDataFilePathCommand + CHAR(10) + @CreateLogFilePathCommand + CHAR(10) + @RestoreDatabaseCommand
		IF @WithRecovery = 1 BEGIN 
			SET @RestoreDatabaseCommand += CHAR(10) + N'GO' + CHAR(10) + @RestoreDBWithRecovery	

			IF @existDBinServer = 1 AND @TargetDBName <> 'master'	BEGIN SET @RestoreDatabaseCommand += CHAR(10) + N'GO' + CHAR(10) + @SetMultiUser	END 
			IF @SetEnableBroker <> ''								BEGIN SET @RestoreDatabaseCommand += CHAR(10) + N'GO' + CHAR(10) + @SetEnableBroker	END 
			IF @KeepDbOwner = 1 AND @ChangeDbOwner IS NOT NULL		BEGIN SET @RestoreDatabaseCommand += CHAR(10) + N'GO' + CHAR(10) + @ChangeDbOwner	END
		END
		SELECT CONVERT(XML, '<!--' + @TargetDBName +  CHAR(10) + @RestoreDatabaseCommand + CHAR(10) + N'GO' + CHAR(10) + '-->') ;
	END
	ELSE BEGIN
		BEGIN TRY
			EXEC sp_executesql @CreateDataFilePathCommand	
			EXEC sp_executesql @CreateLogFilePathCommand	
			EXEC sp_executesql @RestoreDatabaseCommand	
			IF @WithRecovery = 1 BEGIN 
				EXECUTE sp_executesql @RestoreDBWithRecovery

				IF @existDBinServer = 1 AND @TargetDBName <> 'master'	BEGIN EXECUTE sp_executesql @SetMultiUser			END 
				IF @SetEnableBroker <> ''								BEGIN EXECUTE sp_executesql @SetEnableBroker		END 
				IF @KeepDbOwner = 1 AND @ChangeDbOwner IS NOT NULL		BEGIN EXECUTE sp_executesql @ChangeDbOwner			END
			END
		END TRY
		BEGIN CATCH
			SELECT ERROR_MESSAGE()
			--PRINT 'There was an error during the execution of ' + CHAR(10) + @RestoreDatabaseCommand + CHAR(10) + 'Please check the log files for more information.'
			RAISERROR('There was an error during the execution of %s.Please check the log files for more information.', 16, 1, @RestoreDatabaseCommand)
			RETURN -800
		END CATCH
	END
	

	PRINT '/*****************************************'
	PRINT 'RESTORE DATABASE Total Time    : ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @StartTime, GETDATE()) )
	PRINT '*****************************************/'

END
GO
