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
-- Author:		RAG
-- Create date: 16/05/2013
-- Description:	Run DBCC CHECKDB for a given database or all databases
--
-- Parameters:
--				@dbname -> all databases if NULL
--				@batchNo -> only databases within a batch if specified, all databases if NULL
--				@weekDayOverride -> to override the scheduled for the day running
--				@command -> Will run the scheduled valued if NULL, possible values are
--							F -> Runs CHECKDB with no options
--							P -> Runs CHECKDB with PHYSICAL_ONLY
--							A -> Runs CHECKALLOC
--							T -> Runs CHECKTABLE
--							C -> Runs CHECKCATALOG
--				@debugging -> Will run the commands or just print them out if true
--
-- Log History:	
--				17/07/2015	RAG - Added functionality to add WITH DATA_PURITY for legacy databases (flag value = 0)
--								- 	http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
--				25/09/2015	RAG - Added output in table format
--				22/02/2016	RAG - Added history table dbo.DBCC_History
--				11/05/2016	RAG - Changed the case of 'dbi_dbccFlags' check as instances with Case sensitive collation were missing it
--				24/06/2016	RAG - Mofified the scheduling system to store that in a new column in DBA.dbo.DatabaseInformation called [DBCCSchedule]
--								- 	which will hold weekly schedule in a CHAR(7) format
--				29/06/2016	SZO - Removed functionality to exclude databases as this will be handled by [DBCCSchedule] in DBA.dbo.DatabaseInformation.
--				03/07/2016	RAG - Removed parameter @onlySystemDB as DBCC CHECKDB schedule is now per database
--				04/07/2016	RAG	- Added parameter @weekDayOverride which gives functionality to override the day of the week we want to run the process for.
--				18/07/2016	RAG	- Added database name to DBCC DBINFO('@dbname') not to try access the database with USE [dbname] which will make it fail
--									for non readable secondaries
--				13/09/2016	RAG	- Added column ErroNumber to [dbo].[DBCC_History] in case CHECKDB reports any
--				14/09/2016	RAG	- Changed WHILE loop for a cursor
--				12/12/2016	SZO - BUG: Changed the datatype of [DBCC_duration] in the #output table from `time(0)` to `varchar(24)`. 
--				14/12/2016	RAG	- Added functionality to execute separately the different commands that compound CHECKDB
--										- DBCC CHECKALLOC
--										- DBCC CHECKTABLE for each table (by calling new SP DBA_runCHECKTABLE
--										- DBCC CHECKALLOC
--									This new functionality can be called by using the provided parameter @command, or specified in DBA.databaseInformation.DBCCSchedule
--				01/06/2017	RAG	- Added parameter @isPhysicalOnlyOverride
-- 
-- =============================================
CREATE PROCEDURE [dbo].[DBA_runCHECKDB]
	@dbname						SYSNAME = NULL
	, @batchNo					TINYINT	= NULL
	, @weekDayOverride			TINYINT = NULL
	, @command					CHAR(1) = NULL
	, @isPhysicalOnlyOverride	BIT		= NULL
	, @debugging				BIT		= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @sqlString			NVARCHAR(1000)
			, @errorNumber		INT
			, @errorMessage		NVARCHAR(4000)
			, @emailBody		NVARCHAR(1000)
			, @startTime		DATETIME = GETDATE()
			, @startDBCC		DATETIME
			, @isDataPurity		BIT
			, @isPhysicalOnly	BIT
			, @dayOfTheWeek		INT = ISNULL(@weekDayOverride, DATEPART(WEEKDAY, GETDATE()))

	-- Adjust parameters
	SET @debugging		= ISNULL(@debugging, 0)

	IF OBJECT_ID('tempdb..#DBINFO')	IS NOT NULL DROP TABLE #DBINFO

	IF OBJECT_ID('tempdb..#output')	IS NOT NULL DROP TABLE #output

	-- To hold DBCC DBINFO results
	CREATE TABLE #DBINFO(
		 ParentObject	VARCHAR(255) 
		, Object		VARCHAR(255) 
		, Field			VARCHAR(255) 
		, Value			VARCHAR(255) 
	)

	CREATE TABLE #output(
		[name]				SYSNAME
		, DBCC_datetime		DATETIME2(0)
		, DBCC_duration		VARCHAR(24) 
		, isPhysicalOnly	BIT
		, isDataPurity		BIT
		, command			VARCHAR(20)
		, ErrorNumber		INT NULL
	)

	IF @weekDayOverride NOT BETWEEN 1 AND 7  BEGIN 
		RAISERROR ('The value specified for @weekDayOverride is not valid, please specify a value between 1 and 7', 16, 0)
		RETURN -100
	END 

	IF (@dbname IS NULL AND @command IS NOT NULL) BEGIN
		RAISERROR ('@dbname should be specified if @command is specified, please run again with new values', 16, 0)
		RETURN -200
	END

	IF @command NOT IN ('F', 'P', 'A', 'T', 'C') BEGIN 
		SET @errorMessage = 'The value specified for @command is not valid, please specify one of the following' + CHAR(10) +
							'F -> Runs CHECKDB with no options' + CHAR(10) +
							'P -> Runs CHECKDB with PHYSICAL_ONLY' + CHAR(10) +
							'A -> Runs CHECKALLOC' + CHAR(10) +
							'T -> Runs CHECKTABLE' + CHAR(10) +
							'C -> Runs CHECKCATALOG' 
		RAISERROR (@errorMessage, 16, 0)
		RETURN -300
	END

	DECLARE dbs CURSOR LOCAL READ_ONLY FORWARD_ONLY FAST_FORWARD FOR 
		SELECT db.[name]
				, ISNULL(@command, SUBSTRING(d.DBCCSchedule, @dayOfTheWeek, 1)) AS command
			FROM sys.databases AS db
				LEFT JOIN DBA.dbo.DatabaseInformation AS d
					ON d.name = db.name COLLATE DATABASE_DEFAULT
						AND d.server_name = @@SERVERNAME
			WHERE db.state = 0 
				AND db.source_database_id IS NULL -- exclude snapshots
				AND SUBSTRING(d.DBCCSchedule, @dayOfTheWeek, 1) <> '-' 
				AND db.[name] = ISNULL(@dbname, db.[name])
				AND ISNULL(d.backupBatchNo, 0) = ISNULL(@batchNo, 0)
		--UNION 
		---- Include @dbname in debugging mode to see meaningful results
		--SELECT @dbname, @command
		--	WHERE @dbname IS NOT NULL
		--		--AND @debugging = 1
		--	ORDER BY [name]

	OPEN dbs

	FETCH NEXT FROM dbs INTO @dbname, @command

	WHILE @@FETCH_STATUS = 0 BEGIN

		IF @command = 'A' BEGIN
			SET @sqlString = N'DBCC CHECKALLOC (' + QUOTENAME(@dbname) + ') WITH ALL_ERRORMSGS, NO_INFOMSGS' 
		END
		ELSE IF @command = 'T' BEGIN
			SET @sqlString = N'EXECUTE [dbo].[DBA_runCHECKTABLE]
									@dbname			= ''' + @dbname + ''',
									@tableName		= NULL,
									@noIndex		= NULL,
									@tabLock		= NULL,
									@debugging		= @debugging, 
									@errorNumber	= @errorNumber,
									@errorMessage	= @errorMessage' 
		END
		ELSE IF @command = 'C' BEGIN
			SET @sqlString = N'DBCC CHECKCATALOG (' + QUOTENAME(@dbname) + ') WITH NO_INFOMSGS' -- ALL_ERRORMSGS is not valid for CHECKCATALOG
		END
		ELSE BEGIN
				
			SET @sqlString = N'
				USE master;

				TRUNCATE TABLE #DBINFO

				INSERT #DBINFO (ParentObject, Object, Field, Value)
					EXEC (''DBCC DBINFO(''''' + @dbname + ''''') WITH TABLERESULTS, NO_INFOMSGS'');
			';

			EXEC sp_executesql @sqlString

			--SELECT * FROM #DBINFO WHERE Field = 'dbi_DBCCFlags'

			-- Run DBCC CHECKDB with data_purity if never run before
			SET @isDataPurity		= CASE WHEN (SELECT Value FROM #DBINFO WHERE Field = 'dbi_dbccFlags') = 0 THEN 1 ELSE 0 END

			-- Run DBCC CHECKDB with physical_only when DB is over 500GB, but full once every 4 weeks.
			SET @isPhysicalOnly	= CASE 
										WHEN @isPhysicalOnlyOverride IS NOT NULL THEN @isPhysicalOnlyOverride
										WHEN ISNULL(@command, '') = 'P' THEN 1 -- Override by parameter
										WHEN ((SELECT SUM(size/128./1024) 
												FROM sys.master_files 
												WHERE [type] = 0 
													AND DB_NAME(database_id) = @dbname) > 500 
											AND DATEPART(WK, GETDATE()) % 4 <> 0) THEN 1 
										ELSE 0 
									END

			SET @sqlString = N'DBCC CHECKDB (' + QUOTENAME(@dbname) + ') WITH ALL_ERRORMSGS, NO_INFOMSGS' + 
									CASE WHEN @isPhysicalOnly = 1 THEN ', PHYSICAL_ONLY'	ELSE '' END + 
									CASE WHEN @isDataPurity	= 1 THEN ', DATA_PURITY'	ELSE '' END		 

		END

		PRINT CHAR(10) + '--Executing ...' + CHAR(10) + @sqlString + CHAR(10) + 'GO'

		SET @startDBCC = GETDATE()

		IF @debugging = 0 BEGIN
			BEGIN TRY
				EXEC sp_executesql 
						@stmt = @sqlString 
						, @params		= N'@errorNumber INT, @errorMessage NVARCHAR(4000), @debugging BIT'
						, @errorNumber	= @errorNumber 
						, @errorMessage	= @errorMessage
						, @debugging 	= @debugging 
			END TRY
			BEGIN CATCH 		
				
				SELECT @errorNumber		= ERROR_NUMBER()
						, @errorMessage = ERROR_MESSAGE()

				SET @emailBody = @@SERVERNAME + ', ' + @dbname + CHAR(10) + '. The application returned the following error:' + CHAR(10) + @errorMessage
				
				EXEC msdb..sp_send_dbmail	
					@profile_name	= 'Admin Profile', 
					@recipients		= 'DatabaseAdministrators@rws.com', 
					@subject		= 'DBCC CHECKDB Failed', 
					@body			= @emailBody

			END CATCH
		END 

		--PRINT CHAR(10) + '--Execution Time: ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startDBCC, GETDATE()) )

		INSERT INTO #output VALUES (
			@dbname
			, GETDATE() 
			, DBA.dbo.formatSecondsToHR(DATEDIFF (SECOND, @startDBCC, GETDATE()))
			, CASE WHEN @isPhysicalOnly	= 1 THEN 'true' ELSE 'false' END
			, CASE WHEN @isDataPurity		= 1 THEN 'true' ELSE 'false' END
			, CASE 
					WHEN @command = 'A' THEN 'CHECKALLOC'
					WHEN @command = 'T' THEN 'CHECKTABLE'
					WHEN @command = 'C' THEN 'CHECKCATALOG'
					ELSE					 'CHECKDB'
				END
			, @errorNumber
		)

		FETCH NEXT FROM dbs INTO @dbname, @command

	END

	--PRINT CHAR(10) + '/*****************************************'
	--PRINT 'DBCC CHECKDB Total Time        : ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startTime, GETDATE()) )
	--PRINT '*****************************************/'

	-- Only insert if not debugging
	IF @debugging = 0 BEGIN 
		INSERT INTO dbo.DBCC_History (server_name, name, DBCC_datetime, DBCC_duration, isPhysicalOnly, isDataPurity, command, ErrorNumber)
			OUTPUT INSERTED.*
		SELECT @@SERVERNAME AS server_name, name, DBCC_datetime, DBCC_duration, isPhysicalOnly, isDataPurity, command, ErrorNumber
		FROM #output
	END 
	ELSE BEGIN
		SELECT @@SERVERNAME AS server_name, name, DBCC_datetime, DBCC_duration, isPhysicalOnly, isDataPurity, command, ErrorNumber
		FROM #output
	END 
	
	CLOSE dbs
	DEALLOCATE dbs

END
GO
