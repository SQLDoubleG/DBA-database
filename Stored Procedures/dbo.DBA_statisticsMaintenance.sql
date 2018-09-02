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
-- Create date: 28/03/2013 
-- Description:	Update database statistics per index or column (if required) 
-- 
-- Parameters: 
--              - @dbname			-> Name of the database, use NULL for all databases in the instance 
--              - @rowsThreshold    -> Update stats if row counts differ in a number bigger than 
--              - @percentThreshold -> Update stats if row counts differ in a percentage bigger than 
--				- @sample			-> sample size, values can be 'RESAMPLE', 'FULLSCAN', 'SAMPLE nn PERCENT' or 'SAMPLE nn ROWS' 
--              - @debugging		-> will print the statement or execute it 
-- 
-- Log: 
--				28/03/2013	RAG	- Moved sp_updatestats from Weekly Maintenance 
--									- This job to be run on Sundays 3am 
--				25/04/2013	RAG	- Rewriten to use UPDATE STATISTICS instead of sp_updatestats due to CXPACKET waits  
--										Also implemented functionality to determine if stats need to be updated  
--										based on real and stats rowcounts 
--				29/04/2013	RAG	- Updated to execute 2 weeks databases for next execution 
--				13/05/2013	RAG	- Updated to execute all databases for next execution 
--				15/05/2013	RAG	- Created as SP in DBA database which will be replicated accross all the servers  
--										and therefore accessible. 
--				15/05/2016	RAG	- Rewritten to read info from sys.stats and sys.dm_db_stats_properties 
--								- Added new parameters 
--				24/06/2016	RAG	- Added schedule checker 
--				04/07/2016 RAG	- Added parameter @weekDayOverride which gives functionality to override the day of the week we want to run the process for. 
--								- Added @batchNo because now it runs as part of 'Database Maintenance' job(s) 
--								- Assign default values when some parameters are NULL and cannot be 
--				18/07/2016	RAG	- Added validation for PRIMARY replicas in case there are Availability Groups configured 
--				08/12/2016	RAG	- Added validation for parameter @sample 
--				08/12/2016	RAG	- Added parameter @excludeBlobTypes to exclude columns with the following data types: 
--									image, text, uniqueidentifier, sql_variant, ntext, hierarchyid, geography, geometry, varbinary, binary, timestamp, xml 
--				04/01/2018	RAG	- Added columns from [dbo].[DBA_getDatabasesMaintenanceList]
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
--								- Added clause not to run on secondary databases
--				23/03/2018	RAG	- Added INSERT into new table [dbo].[StatsMaintenanceHistory]
--				26/03/2018	RAG	- Added NULLIF(xxx, 0) to avoid divide by zero errors
--				05/04/2018	RAG	- Changed DECIMAL(10,2) to (19,2) as there were some cases that produce overflow
--									 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_statisticsMaintenance] 
	@dbname				SYSNAME			= NULL 
	, @rowsThreshold	INT				= 100000	-- Update stats if row counts differ in a number bigger than 100k 
	, @percentThreshold	DECIMAL(4,1)	= 10.0		-- Update stats if row counts differ in a percentage bigger than 10% 
	, @sample			NVARCHAR(20)	= 'RESAMPLE' 
	, @batchNo			TINYINT			= NULL 
	, @weekDayOverride	TINYINT			= NULL 
	, @excludeBlobTypes BIT				= 0			--  
	, @debugging		BIT				= 0			-- SET TO 0 FOR THE SP TO DO ITS JOB, OTHERWISE WILL JUST PRINT OUT THE STATEMENTS!!!! 
AS 
BEGIN  
	 
	SET NOCOUNT ON 
 
	-- Adjust parameters 
	SET @rowsThreshold		= ISNULL(@rowsThreshold, 100000) 
	SET @percentThreshold	= ISNULL(@percentThreshold, 10.0) 
	SET @sample				= ISNULL(@sample, N'RESAMPLE') 
	SET @excludeBlobTypes	= ISNULL(@excludeBlobTypes, 0) 
	SET @debugging			= ISNULL(@debugging, 0) 
 
	IF @weekDayOverride NOT BETWEEN 1 AND 7  BEGIN  
		RAISERROR ('The value specified for @weekDayOverride is not valid, please specify a value between 1 and 7', 16, 0) 
		RETURN -50 
	END  
 
	IF @sample NOT IN ('RESAMPLE', 'FULLSCAN', 'SAMPLE [1-99] PERCENT', 'SAMPLE % ROWS') BEGIN  
		RAISERROR ('The value specified for @sample is not valid, please specify one of the following ''RESAMPLE'', ''FULLSCAN'', ''SAMPLE % PERCENT'', ''SAMPLE % ROWS''', 16, 0) 
		RETURN -100 
	END  
			 
	DECLARE	@database_name	SYSNAME 
			, @sqlString	NVARCHAR(MAX) 
			, @totalTime	DATETIME 
			, @dayOfTheWeek	INT = ISNULL(@weekDayOverride, DATEPART(WEEKDAY, GETDATE())) 
			 
	DECLARE @db TABLE(database_id INT NOT NULL PRIMARY KEY, name SYSNAME NOT NULL, role TINYINT NOT NULL, secondary_role_allow_connections TINYINT NOT NULL)
 
	SET @totalTime = GETDATE() 
 
	INSERT INTO @db (database_id, name, role, secondary_role_allow_connections)
		EXECUTE [dbo].[DBA_getDatabasesMaintenanceList] 
 
	DECLARE dbs CURSOR LOCAL READ_ONLY FORWARD_ONLY FAST_FORWARD FOR  
		SELECT db.[name]  
			FROM @db AS db 
				INNER JOIN DBA.dbo.DatabaseInformation AS d 
					ON d.name = db.name COLLATE DATABASE_DEFAULT 
						AND d.server_name = @@SERVERNAME 
			WHERE ISNULL(d.backupBatchNo, 0) = ISNULL(@batchNo, 0) 
				AND SUBSTRING(d.StatisticsMaintenanceSchedule, @dayOfTheWeek, 1) <> '-' -- Remove one day from @dayOfTheWeek to read the actual position and not from that 
				AND @dbname IS NULL 
				AND db.role = 1 -- primary
		UNION  
		-- Specified database if any 
		SELECT [name]  
			FROM @db AS db 
			WHERE db.name LIKE @dbname 
			ORDER BY [name] 
 
	OPEN dbs 
 
	FETCH NEXT FROM dbs INTO @database_name 
 
	WHILE @@FETCH_STATUS = 0 BEGIN 
 
		PRINT CHAR(13) + 'Processing database: ' + QUOTENAME(@database_name) 
	 
		SET @sqlString = N' 
		 
USE ' + QUOTENAME(@database_name) + N' 
 
SET NOCOUNT ON 
 
DECLARE @timestamp						DATETIME  
DECLARE @timePerStats					DATETIME 
DECLARE @update_stats					NVARCHAR(1000) 

DECLARE @server_name					SYSNAME
DECLARE @database_id					INT
DECLARE @database_name					SYSNAME
DECLARE @object_id						INT
DECLARE @schema_name					SYSNAME
DECLARE @object_name					SYSNAME
DECLARE @stats_id						INT
DECLARE @stats_name						SYSNAME
DECLARE @auto_created					BIT
DECLARE @table_row_count				INT
DECLARE @stats_row_count				INT
DECLARE @stats_last_updated				DATETIME2(3)
DECLARE @rows_sampled					INT
DECLARE @percentage_sampled				DECIMAL(19,2)
DECLARE @real_percentage_sampled		DECIMAL(19,2)
DECLARE @stats_modification_counter		INT
DECLARE @stats_modification_percentage	DECIMAL(19,2)	
DECLARE @DataCollectionTime				DATETIME2(3)
DECLARE @Duration_seconds				INT

DECLARE @startDate						DATETIME
 
PRINT CHAR(9) + N''Updating stats for database : '' + QUOTENAME(DB_NAME())  
 
DECLARE cur CURSOR READ_ONLY FORWARD_ONLY FAST_FORWARD FOR  
 
SELECT	 
		''UPDATE STATISTICS '' +  
			QUOTENAME(OBJECT_SCHEMA_NAME(ix.object_id)) + ''.'' + QUOTENAME(OBJECT_NAME(ix.object_id)) + '' '' + QUOTENAME(st.name) +  
			'' WITH '' + @sample AS update_stats 

		, @@SERVERNAME AS server_name
		, DB_ID() AS database_id
		, DB_NAME() AS database_name
		, ix.object_id 
		, OBJECT_SCHEMA_NAME(ix.object_id) AS [schema_name] 
		, OBJECT_NAME(ix.object_id) AS [object_name] 
		, st.stats_id 
		, st.name AS stats_name
		, st.auto_created 
		, pst.row_count AS table_row_count
		, stp.rows AS stats_row_count
		, stp.last_updated AS stats_last_updated
		, stp.rows_sampled 
		, ISNULL(CONVERT(DECIMAL(19,2), stp.rows_sampled * 100. / NULLIF(stp.rows, 0)), 0) AS percentage_sampled
		, ISNULL(CONVERT(DECIMAL(19,2), stp.rows_sampled * 100. / NULLIF(pst.row_count, 0)), 0) AS real_percentage_sampled
		, stp.modification_counter AS stats_modification_counter
		, ISNULL(CONVERT(DECIMAL(19,2), stp.modification_counter * 100. / NULLIF(stp.rows, 0)), 0) AS stats_modification_percentage
		, GETDATE() AS DataCollectionTime
		, 0 AS duration_seconds

		--, ''DBCC SHOW_STATISTICS ('''''' + OBJECT_SCHEMA_NAME(ix.object_id) + ''.'' + OBJECT_NAME(ix.object_id) + '''''', '''''' + st.name + '''''')'' AS DBCC_SHOW_STATISTICS 
	FROM sys.indexes AS ix 
		INNER JOIN sys.dm_db_partition_stats AS pst 
			ON pst.object_id = ix.object_id 
				AND pst.index_id = ix.index_id  
		LEFT JOIN sys.stats AS st 
			ON st.object_id = ix.object_id 
		OUTER APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) AS stp 
 
		--OUTER APPLY (SELECT STUFF( 
		--				(SELECT '', '' + c.name AS name FROM sys.columns AS c 
		--				INNER JOIN sys.stats_columns AS stc  
		--					ON stc.column_id = c.column_id 
		--						AND stc.object_id = c.object_id 
		--				WHERE stc.stats_id = st.stats_id 
		--					AND stc.object_id = st.object_id 
		--				FOR XML PATH(''''), TYPE).value(''.'', ''nvarchar(max)''), 1, 2, N'''') 
		--			) AS stc(column_list) 
 
	WHERE ix.type IN (0, 1) 
		AND OBJECTPROPERTYEX(ix.object_id, ''IsMSShipped'') = 0 
		AND stp.modification_counter > 0 
 
		-- Filter by number of rows or percentage 
		AND ( stp.modification_counter >= @rowsThreshold OR stp.modification_counter >= pst.row_count * (@percentThreshold / 100) ) 
 
		AND (@excludeBlobTypes = 0 OR 
		 
				NOT EXISTS (SELECT *  
							FROM sys.stats_columns AS stc  
								INNER JOIN sys.columns AS c  
									ON stc.object_id = c.object_id  
										AND stc.column_id = c.column_id 
							WHERE stc.object_id = st.object_id 
								AND stc.stats_id = st.stats_id 
								AND (c.user_type_id IN(34,35,36,98,99,128,129,130,165,173,189,241) 
									-- image, text, uniqueidentifier, sql_variant, ntext, hierarchyid, geography, geometry, varbinary, binary, timestamp, xml 
									OR c.max_length = -1   
									-- MAX data types 
									) 
						) 
			) 
 
	ORDER BY stp.last_updated ASC 
 
OPEN cur 
 
FETCH NEXT FROM cur INTO @update_stats, @server_name, @database_id, @database_name, @object_id, @schema_name, @object_name, @stats_id
					, @stats_name, @auto_created, @table_row_count, @stats_row_count, @stats_last_updated, @rows_sampled 
					, @percentage_sampled, @real_percentage_sampled, @stats_modification_counter
					, @stats_modification_percentage, @DataCollectionTime, @Duration_seconds


 
WHILE @@FETCH_STATUS = 0 BEGIN 
				 
	SET @timestamp	= GETDATE() 
 
	PRINT @update_stats 
	PRINT ''Rows in Table			-> '' +  RIGHT(REPLICATE('' '', 12) + CONVERT(VARCHAR, @table_row_count)			, 12) 
	PRINT ''Rows in Stats			-> '' +  RIGHT(REPLICATE('' '', 12) + CONVERT(VARCHAR, @stats_row_count)			, 12) 
	PRINT ''Modification Counter	-> '' +  RIGHT(REPLICATE('' '', 12) + CONVERT(VARCHAR, @stats_modification_counter)	, 12) 
			 
	IF @debugging = 0 BEGIN 

		SET @startDate = GETDATE()

		EXECUTE sp_executesql @update_stats 
		
		INSERT INTO [DBA].[dbo].[StatsMaintenanceHistory] ([server_name], [database_id]
			, [database_name], [object_id], [schema_name], [object_name], [stats_id]
			, [stats_name], [auto_created], [table_row_count], [stats_row_count]
			, [stats_last_updated], [rows_sampled], [percentage_sampled]
			, [real_percentage_sampled], [stats_modification_counter]
			, [stats_modification_percentage], [DataCollectionTime], [Duration_seconds])
		VALUES (@server_name, @database_id, @database_name, @object_id, @schema_name, @object_name, @stats_id
			, @stats_name, @auto_created, @table_row_count, @stats_row_count, @stats_last_updated, @rows_sampled 
			, @percentage_sampled, @real_percentage_sampled, @stats_modification_counter
			, @stats_modification_percentage, @DataCollectionTime, DATEDIFF(SECOND, @startDate, GETDATE()))

	END  
			 
	PRINT ''Time to update stats	-> '' + RIGHT(REPLICATE('' '', 12) + DBA.dbo.formatSecondsToHR(DATEDIFF(ss, @timestamp, GETDATE())) COLLATE DATABASE_DEFAULT, 12) + CHAR(10) 
			 
	FETCH NEXT FROM cur INTO @update_stats, @server_name, @database_id, @database_name, @object_id, @schema_name, @object_name, @stats_id
					, @stats_name, @auto_created, @table_row_count, @stats_row_count, @stats_last_updated, @rows_sampled 
					, @percentage_sampled, @real_percentage_sampled, @stats_modification_counter
					, @stats_modification_percentage, @DataCollectionTime, @Duration_seconds 
 
END 
 
CLOSE cur 
DEALLOCATE cur' 
 
		--PRINT @sqlString 
		EXEC sp_executesql 
				@stmt = @sqlString 
				, @params = N'@debugging BIT, @rowsThreshold INT, @percentThreshold DECIMAL(4,1), @sample NVARCHAR(20), @excludeBlobTypes BIT' 
				, @debugging		= @debugging 
				, @rowsThreshold	= @rowsThreshold 
				, @percentThreshold = @percentThreshold 
				, @sample			= @sample 
				, @excludeBlobTypes	= @excludeBlobTypes 
 
 
		FETCH NEXT FROM dbs INTO @database_name 
 
	END 
 
	CLOSE dbs 
	DEALLOCATE dbs 
 
	PRINT CHAR(13) + '/********************************************************' 
	PRINT N'Total Time taken              : ' + RIGHT( REPLICATE(' ', 24) + DBA.dbo.formatSecondsToHR(DATEDIFF(ss, @totalTime, GETDATE())) COLLATE DATABASE_DEFAULT, 24) 
	PRINT '********************************************************/' 
END 
GO
