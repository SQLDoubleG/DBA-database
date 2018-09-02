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
-- Create date: 2013/06/05
-- Description:	Restores databases from the last backup to run CHECKDB on them
-- Log:
--				2013/06/05	RAG. Created as SP in DBA database
--								- Backup Path is now taken from DBA.dbo.InstaceInformation
--								- Added parameters @debugging and @databaseName
--								- Removed master from the databases to be restored and run CHECKDB
--									(http://sqlmag.com/blog/my-master-database-really-corrupt)
--								- CHECKDB runs now in [master] database for all RWSSQLBLADE1 instances in the job 'Daily Maintenance'
--				2013/06/07	RAG. Modified to send email only in case of errors
--				2013/07/15	RAG. SP completely rewritten to take advantage of the the SP's 
--								- DBA.dbo.DBA_restoreDBfromBackup. Restores a backup from DISK, improvements include the backup can be distributed across 
--									multiple files
--								- DBA.dbo.DBA_runCHECKB. Run DBCC CHECKDB for a given DB, improvements include tweacks for PB_ databases
--				2016/03/01	RAG. Added check to exclude is_read_only databases as those are excluded from the backup job
--				2016/04/25	RAG. Changed backupschedule check to '-------' due to changes in the column
--				2016/07/21	RAG. Changed call to [dbo].[DBA_restoreDBfromBackup] to add new parameters
--
--Requirements:
--				SQL service account has access & permissions to the file location given.
--				xp_cmdshell is enabled on the server. 
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_runCHECKDB_onBackups]
	@SourceInstanceName		SYSNAME
	, @dbname				SYSNAME			= NULL
	, @dbfilesPath			NVARCHAR(512)	= NULL
	, @debugging			BIT				= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
AS
BEGIN
	
	SET NOCOUNT ON
	SET QUOTED_IDENTIFIER ON

	DECLARE @Pos			INT
			, @MaxId		INT 
			, @targetdbname SYSNAME
			, @startTime	DATETIME = GETDATE()

	DECLARE @retVal			INT 
			, @errorMsg		NVARCHAR(1000) = N''
			, @DropDB		NVARCHAR(1000) = N''
			, @emailSubject	NVARCHAR(255)
	
	DECLARE @Databases TABLE 
		( ID			INT IDENTITY NOT NULL
		, dbname		SYSNAME
		, backupRootPath NVARCHAR(256) NULL)
 
	PRINT '/*****************************************'
	PRINT 'Starting Process @  : ' + CONVERT(VARCHAR,@startTime, 120)
	PRINT '*****************************************/'

	-- Get list of databases, based on the data collected into the DBA database by SQL Auditing Job
	INSERT INTO @Databases (dbname, backupRootPath)
		SELECT TOP 100 PERCENT
				D.name
				, [DBA].dbo.getBackupRootPath(D.server_name, D.name)
			FROM [DBA].[dbo].[DatabaseInformation] AS D
			WHERE ( d.state_desc = 'ONLINE' OR @debugging = 1 ) -- Online databases or debugging
				AND D.server_name = @SourceInstanceName
				AND D.is_read_only = 0 -- exclude read_only databases
				AND D.backupSchedule <> '-------' -- Only databases which perform backups
				AND D.name LIKE ISNULL(@dbname, D.name) 
				AND D.name NOT IN ('master', 'tempdb', 'model') -- IMPORTANT NOT TO RESTORE MASTER 
			ORDER BY [name] ASC

	--SELECT * FROM @Databases

	IF NOT EXISTS (SELECT 1 FROM @Databases) BEGIN
		SET @errorMsg = 'There are no databases which match the current request'
		RAISERROR (@errorMsg, 16, 1)
	END 
		
	IF OBJECT_ID('DBA.dbo.CheckDBResults', 'U') IS NOT NULL BEGIN
		DROP TABLE DBA.dbo.CheckDBResults;
	END
	-- Create table to store results so they can be emailed (email query is in a different session so can't use temp table or table variable).
	CREATE TABLE DBA.dbo.CheckDBResults (dbname NVARCHAR(255), ErrorCode INT)
	DECLARE @DBCCResult INT

	SELECT @Pos = MIN(ID)
			, @MaxId = MAX(ID) 
		FROM @Databases

	WHILE @Pos <= @MaxId BEGIN
		
		SET @dbname = ( SELECT dbname FROM @Databases WHERE ID = @Pos )
		SET @targetdbname = @dbname + N'_checkDB'
		SET @DropDB = N'DROP DATABASE ' + QUOTENAME(@targetdbname) + ';' 

		BEGIN TRY 

			EXECUTE [dbo].[DBA_restoreDBfromBackup] 
				@SourceInstanceName	= @SourceInstanceName
				,@SourceDBName		= @dbname
				,@TargetDBName		= @targetdbname
				,@SourceFileName	= NULL
				,@RestoreLastBackup = 1
				,@SourceFilePath	= NULL
				,@NewDataFilePath	= @dbfilesPath
				,@NewLogFilePath	= @dbfilesPath
				,@WithStopAt		= NULL
				,@WithReplace		= 1
				,@WithRecovery		= 1
				,@WithStats			= 0
				,@KeepDbOwner		= 0
				,@debugging			= @debugging

			EXECUTE @DBCCResult = [DBA].[dbo].[DBA_runCHECKDB]
				@dbname				= @targetdbname
				, @debugging		= @debugging

			INSERT INTO DBA.dbo.CheckDBResults (dbname, ErrorCode) VALUES (@dbname, @DBCCResult);
		
			PRINT CHAR(10) + @DropDB + CHAR(10) + 'GO'

			IF ISNULL(@debugging, 0) = 0 BEGIN
				EXEC sp_executesql @DropDB
			END

		END TRY 

		BEGIN CATCH
		
			-- Once all done, read the table & email results if there was any error
			SET @emailSubject = 'Error Running CheckDB on backups for database ' + QUOTENAME(@dbname) + ' from instance ' + QUOTENAME(@SourceInstanceName)

			SET @errorMsg = ERROR_MESSAGE()

			EXEC msdb.dbo.sp_send_dbmail 
				@profile_name	= 'Admin Profile', 
				@recipients		= 'DatabaseAdministrators@rws.com', 
				@subject		= @emailSubject,
				@body			= @errorMsg,  
				@body_format	= 'TEXT';

		END CATCH
		
		SELECT @Pos = MIN(ID)
			FROM @Databases
			WHERE ID > @Pos

	END
	
	IF EXISTS (SELECT 1 FROM DBA.dbo.CheckDBResults WHERE ErrorCode <> 0) BEGIN
		-- Once all done, read the table & email results if there was any error
		SET @emailSubject = 'DBCC CheckDB Results for ' + QUOTENAME(@SourceInstanceName)

		EXEC msdb.dbo.sp_send_dbmail 
			@profile_name = 'Admin Profile', 
			@recipients = 'DatabaseAdministrators@rws.com', 
			@subject = @emailSubject,
			@body = '',  
			@body_format = 'TEXT', 
			@query_result_width = 50, 
			@query_result_no_padding = 1,
			@query = 'SET NOCOUNT ON; SELECT CAST(dbname AS VARCHAR(100)) AS dbname, CAST(ErrorCode AS VARCHAR(5)) AS ErrorCode FROM DBA.dbo.CheckDBResults ORDER BY dbname',
			@execute_query_database = 'DBA', 
			@attach_query_result_as_file = 0, 
			@query_result_header = 1, 
			@append_query_error = 1;
	END

	--Remove results table.
	DROP TABLE DBA.dbo.CheckDBResults;

	PRINT '/*****************************************'
	PRINT 'Total Time                     : ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startTime, GETDATE()) )
	PRINT '*****************************************/'

END


GO
