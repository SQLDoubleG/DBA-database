SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2019 Raul Gonzalez, @SQLDoubleG (RAG)
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
-- Author:		Raul Gonzalez, @SQLDoubleG (RAG)
-- Create date: 11/11/2019
-- Description:	This script will return information collected by the query store
--
-- Assumptions:	The script will work on any version of the query store (SQL Server 2016 onward)
--
-- Parameters:	
--				- @dateFro
--				- @dateTo		
--				- @topNrows	
--				- @OrderBy	
--
-- Log History:	
--				11/11/2019  RAG - Created
--				18/11/2019  RAG - Added average wait times per wait type
--				24/01/2021  RAG - Added functionality to go through all databaes
--
-- =============================================

DECLARE @dbname	    SYSNAME		= NULL
DECLARE @dateFrom	DATETIME2	= DATEADD(DAY, -8, GETDATE())
DECLARE @dateTo		DATETIME2	= GETDATE()
DECLARE @topNrows	INT
DECLARE @OrderBy	SYSNAME = 'total_cpu'

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

DECLARE @sqlstring		NVARCHAR(MAX) 
		, @sqlstringdb	NVARCHAR(MAX) 
		, @countDBs		INT = 1 
		, @numDBs		INT 

DECLARE @databases TABLE  
		( ID			INT IDENTITY 
		, dbname		SYSNAME) 

IF OBJECT_ID('tempdb..#intervals')	IS NOT NULL DROP TABLE #intervals
IF OBJECT_ID('tempdb..#waits')		IS NOT NULL DROP TABLE #waits
IF OBJECT_ID('tempdb..#totals')		IS NOT NULL DROP TABLE #totals
IF OBJECT_ID('tempdb..#output')		IS NOT NULL DROP TABLE #output

CREATE TABLE #intervals(
	[database_name]					SYSNAME NULL
	, [runtime_stats_interval_id]	BIGINT	NULL
	, [start_time]					DATETIMEOFFSET NULL
	, [end_time]					DATETIMEOFFSET NULL)

CREATE TABLE #waits(
	[database_name]                         SYSNAME NULL
    , [plan_id]								BIGINT	NULL
	, [avg_query_wait_time_ms]				FLOAT	NULL
	, [total_query_wait_time_ms]			BIGINT	NULL
	, [total_query_wait_time_ms_breakdown]	NVARCHAR(4000) NULL)

CREATE TABLE #totals(
	 [database_name]		SYSNAME NULL
	, [total_executions]	BIGINT NULL
	, [total_duration]		FLOAT NULL
	, [total_cpu]			FLOAT NULL
	, [total_reads]			FLOAT NULL
	, [total_writes]		FLOAT NULL
)

CREATE TABLE #output(
	[Id]									INT IDENTITY NOT NULL
	, [database_name]						SYSNAME	NULL
	, [start_time]							DATETIMEOFFSET NULL
	, [end_time]							DATETIMEOFFSET NULL
	, [query_id]							BIGINT	NULL
	, [plan_id]								BIGINT	NULL
	, [object_name]							SYSNAME NULL
	, [total_executions]					BIGINT NULL
	, [total_duration_ms]					BIGINT NULL
	, [total_cpu_ms]						BIGINT NULL
	, [total_reads]							BIGINT NULL
	, [total_writes]						BIGINT NULL
	, [total_query_wait_time_ms]			BIGINT NULL
	, [total_query_wait_time_ms_breakdown]	NVARCHAR(4000) NULL
	, [avg_duration_ms]						BIGINT NULL
	, [avg_cpu_time_ms]						BIGINT NULL
	, [avg_logical_io_reads]				BIGINT NULL
	, [avg_logical_io_writes]				BIGINT NULL
	, [avg_query_wait_time_ms]				BIGINT NULL
	, [percentge_duration]					DECIMAL(5,2) NULL
	, [percentge_cpu]						DECIMAL(5,2) NULL
	, [percentge_reads]						DECIMAL(5,2) NULL
	, [percentge_writes]					DECIMAL(5,2) NULL
	, [percentage_query_wait_time_ms]		DECIMAL(5,2) NULL
	, [query_sql_text]						XML NULL
	, [query_plan]							XML NULL
)




SET @dateTo		= ISNULL(@dateTo, DATEADD(DAY, 7, @dateFrom)) -- one week
SET @topNrows	= ISNULL(@topNrows, 10)
SET @OrderBy	= ISNULL(@OrderBy, 'total_cpu')

DECLARE @EngineEdition	INT	= CONVERT(INT, SERVERPROPERTY('EngineEdition'))
DECLARE @numericVersion INT = CONVERT(INT, PARSENAME(CONVERT(SYSNAME, SERVERPROPERTY('ProductVersion')),4))

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

INSERT INTO @databases  
	SELECT TOP 100 PERCENT name  
		FROM sys.databases  
		WHERE is_query_store_on = 1
			AND name LIKE ISNULL(@dbname, name) 
		ORDER BY name ASC		 
SET @numDBs = @@ROWCOUNT 

IF @OrderBy NOT IN ('total_executions', 'avg_duration', 'avg_cpu_time', 'avg_logical_io_reads', 'avg_logical_io_writes'
					, 'total_duration', 'total_cpu', 'total_reads', 'total_writes') BEGIN 
	RAISERROR ('The possible values for @OrderBy are the following:
- total_executions
- avg_duration
- avg_cpu_time
- avg_logical_io_reads
- avg_logical_io_writes
- total_duration
- total_cpu			
- total_reads		
- total_writes		

Please Choose on of them and run it again', 16, 0) WITH NOWAIT;
	--GOTO OnError
END

-- Get all the intervals within the DateFrom and DateTo specified
DECLARE @sql NVARCHAR(MAX) = 'USE [?]
	SELECT DB_NAME()
			, runtime_stats_interval_id
			, start_time
			, end_time
		FROM sys.query_store_runtime_stats_interval
		WHERE start_time <= @dateTo
			AND end_time >= @dateFrom'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE Id = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

	INSERT INTO #intervals ([database_name], [runtime_stats_interval_id], [start_time], [end_time])
	EXECUTE sp_executesql 
		@sqlstmt	= @sqlstringdb
		, @params	= N'@dateFrom DATETIME2, @dateTo DATETIME2'
		, @dateFrom = @dateFrom 
		, @dateTo	= @dateTo
        
    SET @countDBs = @countDBs + 1;
END;
SET @countDBs = 1; -- Reset for next loops

--SELECT * FROM #intervals

-- Capture Wait Stats if 2017 or higher
SET @sql = 'USE [?]
SELECT DB_NAME()
        , w.plan_id
		, AVG(w.avg_query_wait_time_ms) AS avg_query_wait_time_ms
		, SUM(w.total_query_wait_time_ms) AS total_query_wait_time_ms
		, STRING_AGG(w.wait_category_desc + '' (Total: '' + CONVERT(VARCHAR(30), w.total_query_wait_time_ms) + '' - Avg: '' + CONVERT(VARCHAR(30), w.avg_query_wait_time_ms) + '')'', '', '') 
			WITHIN GROUP(ORDER BY w.total_query_wait_time_ms DESC) AS total_query_wait_time_ms_breakdown
	FROM (
		SELECT w.plan_id
			   , w.wait_category_desc
			   , AVG(avg_query_wait_time_ms) AS avg_query_wait_time_ms
			   , SUM(w.total_query_wait_time_ms) AS total_query_wait_time_ms
			FROM sys.query_store_wait_stats AS w
				INNER JOIN #intervals AS rsti
					ON rsti.runtime_stats_interval_id = w.runtime_stats_interval_id
						AND rsti.database_name = DB_NAME() COLLATE DATABASE_DEFAULT
			GROUP BY w.plan_id
					 , w.wait_category_desc
	) AS w
	GROUP BY w.plan_id;'

IF CAST(CAST(SERVERPROPERTY('ProductVersion') AS varchar(4)) as decimal(4,2)) > 13 BEGIN
	WHILE @countDBs <= @numDBs BEGIN 
        SET @dbname = (SELECT dbname FROM @databases WHERE Id = @countDBs)
		SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

        INSERT INTO #waits (database_name, plan_id, [avg_query_wait_time_ms], total_query_wait_time_ms, total_query_wait_time_ms_breakdown)
	    EXECUTE sp_executesql @sqlstmt = @sqlstringdb
        
        SET @countDBs = @countDBs + 1;
    END;
END
ELSE BEGIN
	INSERT INTO #waits (plan_id, [avg_query_wait_time_ms], total_query_wait_time_ms, total_query_wait_time_ms_breakdown)
	VALUES (0, 0, 0, N'n/a')
END
SET @countDBs = 1; -- Reset for next loops

--SELECT * FROM #waits


-- Get the totals for the period defined.
SET @sql = 'USE [?]

SELECT DB_NAME()
		, SUM(rst.count_executions) AS total_executions
		, SUM(rst.count_executions * rst.avg_duration) AS total_duration
		, SUM(rst.count_executions * rst.avg_cpu_time) AS total_cpu
		, SUM(rst.count_executions * rst.avg_logical_io_reads) AS total_reads
		, SUM(rst.count_executions * rst.avg_logical_io_writes) AS total_writes
	FROM sys.query_store_runtime_stats AS rst
	INNER JOIN #intervals AS rsti
		ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id
			AND rsti.database_name = DB_NAME() COLLATE DATABASE_DEFAULT'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE Id = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

    INSERT INTO #totals([database_name], [total_executions], [total_duration], [total_cpu], [total_reads], [total_writes])
	EXECUTE sp_executesql @sqlstmt = @sqlstringdb
        
    SET @countDBs = @countDBs + 1;
END;
SET @countDBs = 1; -- Reset for next loops

--SELECT * FROM #totals


-- Get the final output for the period defined.
SET @sql = 'USE [?]
SELECT DB_NAME() AS database_name
		, rst.start_time
		, rst.end_time
		, qp.query_id
		, rst.plan_id
		, ISNULL(OBJECT_SCHEMA_NAME(q.object_id) + ''.'' + OBJECT_NAME(q.object_id), ''-'') AS object_name
		, rst.total_executions
	
	-- totals
		, CONVERT(BIGINT, rst.total_duration / 1000)	AS total_duration_ms
		, CONVERT(BIGINT, rst.total_cpu / 1000)		AS total_cpu_ms
		, rst.total_reads
		, rst.total_writes
		, ISNULL(w.total_query_wait_time_ms					, 0) AS total_query_wait_time_ms			 
		, ISNULL(w.total_query_wait_time_ms_breakdown		, ''-'') AS total_query_wait_time_ms_breakdown

	-- averages
		, ISNULL(CONVERT(BIGINT, rst.avg_duration / 1000	), 0) AS avg_duration_ms
		, ISNULL(CONVERT(BIGINT, rst.avg_cpu_time / 1000	), 0) AS avg_cpu_time_ms
		, ISNULL(CONVERT(BIGINT, rst.avg_logical_io_reads	), 0) AS avg_logical_io_reads
		, ISNULL(CONVERT(BIGINT, rst.avg_logical_io_writes	), 0) AS avg_logical_io_writes
		, ISNULL(CONVERT(BIGINT, w.avg_query_wait_time_ms	), 0) AS avg_query_wait_time_ms

	-- percentages 
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_duration	* 100 / NULLIF(t.total_duration, 0)		), 0)	AS percentge_duration
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_cpu		* 100 / NULLIF(t.total_cpu, 0)			), 0)	AS percentge_cpu
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_reads		* 100 / NULLIF(t.total_reads, 0)		), 0)	AS percentge_reads
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_writes		* 100 / NULLIF(t.total_writes, 0)		), 0)	AS percentge_writes
		, ISNULL(CONVERT(DECIMAL(5,2), w.total_query_wait_time_ms * 100. / NULLIF(tw.total_query_wait_time_ms, 0)), 0) AS percentage_query_wait_time_ms

	-- Query Text and Plan 
		--, qt.query_sql_text
		--, qp.query_plan
		, ISNULL(TRY_CONVERT(XML, ''<!--'' + REPLACE(qt.query_sql_text, ''--'', ''/* this line was commented out */'') + ''-->''), qt.query_sql_text) AS query_sql_text
		, ISNULL(TRY_CONVERT(XML, qp.query_plan), qp.query_plan) AS query_plan

	FROM (
		SELECT TOP (@topNrows) 
				CONVERT(DATETIME2(0), MIN(rsti.start_time)) AS start_time
				, CONVERT(DATETIME2(0), MAX(rsti.end_time)) AS end_time
				, rst.plan_id
				, SUM(rst.count_executions) AS total_executions
				-- averages
				, AVG(rst.avg_duration) AS avg_duration		   
				, AVG(rst.avg_cpu_time) AS avg_cpu_time		   
				, AVG(rst.avg_logical_io_reads) AS avg_logical_io_reads 
				, AVG(rst.avg_logical_io_writes) AS avg_logical_io_writes
				-- totals
				, SUM(rst.count_executions * rst.avg_duration)			AS total_duration
				, SUM(rst.count_executions * rst.avg_cpu_time)			AS total_cpu
				, SUM(rst.count_executions * rst.avg_logical_io_reads)	AS total_reads
				, SUM(rst.count_executions * rst.avg_logical_io_writes) AS total_writes
				--, 		* 
		-- SELECT *
			FROM sys.query_store_runtime_stats AS rst
			INNER JOIN #intervals AS rsti
				ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id 
					AND rsti.database_name = DB_NAME() COLLATE DATABASE_DEFAULT
			GROUP BY rst.plan_id
			ORDER BY  CASE WHEN @OrderBy = ''total_executions''			COLLATE DATABASE_DEFAULT THEN SUM(rst.count_executions) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''avg_duration''				COLLATE DATABASE_DEFAULT THEN AVG(rst.avg_duration) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''avg_cpu_time''				COLLATE DATABASE_DEFAULT THEN AVG(rst.avg_cpu_time) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''avg_logical_io_reads''		COLLATE DATABASE_DEFAULT THEN AVG(rst.avg_logical_io_reads) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''avg_logical_io_writes''	COLLATE DATABASE_DEFAULT THEN AVG(rst.avg_logical_io_writes) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''total_duration''			COLLATE DATABASE_DEFAULT THEN SUM(rst.count_executions * rst.avg_duration) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''total_cpu''				COLLATE DATABASE_DEFAULT THEN SUM(rst.count_executions * rst.avg_cpu_time) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''total_reads''				COLLATE DATABASE_DEFAULT THEN SUM(rst.count_executions * rst.avg_logical_io_reads) ELSE NULL END DESC
					, CASE WHEN @OrderBy = ''total_writes''				COLLATE DATABASE_DEFAULT THEN SUM(rst.count_executions * rst.avg_logical_io_writes) ELSE NULL END DESC
		) AS rst
		INNER JOIN sys.query_store_plan AS qp
			ON qp.plan_id = rst.plan_id
		INNER JOIN sys.query_store_query AS q
			ON q.query_id = qp.query_id
		INNER JOIN sys.query_store_query_text AS qt
			ON qt.query_text_id = q.query_text_id 
		LEFT JOIN #waits AS w
			ON w.plan_id = qp.plan_id
				AND w.database_name = DB_NAME() COLLATE DATABASE_DEFAULT
		OUTER APPLY (SELECT * FROM #totals WHERE #totals.database_name = DB_NAME() COLLATE DATABASE_DEFAULT) AS t
		OUTER APPLY (SELECT SUM(total_query_wait_time_ms) AS total_query_wait_time_ms FROM #waits WHERE #waits.database_name = DB_NAME() COLLATE DATABASE_DEFAULT) AS tw
	--WHERE rst.plan_id = 1999
	ORDER BY CASE WHEN @OrderBy = ''total_executions''			COLLATE DATABASE_DEFAULT THEN rst.total_executions ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_duration''				COLLATE DATABASE_DEFAULT THEN rst.avg_duration ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_cpu_time''				COLLATE DATABASE_DEFAULT THEN rst.avg_cpu_time ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_logical_io_reads''		COLLATE DATABASE_DEFAULT THEN rst.avg_logical_io_reads ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_logical_io_writes''	COLLATE DATABASE_DEFAULT THEN rst.avg_logical_io_writes ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_duration''			COLLATE DATABASE_DEFAULT THEN rst.total_duration	ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_cpu''				COLLATE DATABASE_DEFAULT THEN rst.total_cpu ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_reads''				COLLATE DATABASE_DEFAULT THEN rst.total_reads ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_writes''				COLLATE DATABASE_DEFAULT THEN rst.total_writes ELSE NULL END DESC
'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE Id = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

	INSERT INTO #output ([database_name], [start_time], [end_time], [query_id], [plan_id], [object_name]
						, [total_executions], [total_duration_ms], [total_cpu_ms], [total_reads], [total_writes], [total_query_wait_time_ms], [total_query_wait_time_ms_breakdown]
						, [avg_duration_ms], [avg_cpu_time_ms], [avg_logical_io_reads], [avg_logical_io_writes], [avg_query_wait_time_ms]
						, [percentge_duration], [percentge_cpu], [percentge_reads], [percentge_writes], [percentage_query_wait_time_ms]
						, [query_sql_text], [query_plan])
	EXECUTE sp_executesql 
		@sqlstmt	= @sqlstringdb
		, @params	= N'@topNrows INT, @OrderBy SYSNAME'
		, @topNrows = @topNrows 
		, @OrderBy	= @OrderBy
        
    SET @countDBs = @countDBs + 1;
END;

SELECT * 
FROM #output
ORDER BY Id

OnError:
GO