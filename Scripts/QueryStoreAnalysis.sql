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
--              - @dbname
--				- @dateFrom
--				- @dateTo		
--				- @topNrows	
--				- @objectName 
--				- @queryId	
--				- @planId	
--				- @OrderBy	
--
-- Log History:	
--				11/11/2019  RAG - Created
--				18/11/2019  RAG - Added average wait times per wait type
--				24/01/2021  RAG - Added functionality to go through all databaes
--				05/03/2021  RAG - Added parameter @objectName, which will accept values in the format "schema.object_name" 
--				26/03/2021  RAG - Changes:
--									- Added parameter @queryId, to display only one query
--									- Added parameter @planId, to display only one plan
--									- Changed values for sorting on averages to simplify
--				30/03/2021  RAG - Changes in the behaviour:
--									- When passing either @objectName, @queryId or @planId, it will display data per interval so 
--										you can see how the query is performing through the selected period
--				13/04/2021  RAG - @objectId will be calculated from @objectName in advance
--				29/04/2021  RAG - Changes:
--                                  - Fixed bug when sorting if object/query/plan was passed
--                                  - Return interval in SMALLDATETIME
--				11/06/2021  RAG - Changes:
--                                  - Added physical reads
--				01/12/2021	RAG	- Changes
--									- Changed some column names to match others (avg)
--									- Added validation in case object does not exist
--
-- SELECT * FROM sys.databases WHERE is_query_store_on =1 
-- =============================================

DECLARE @dbname	    sysname			= NULL
DECLARE @dateFrom	datetime2		= DATEADD(DAY, -8, GETDATE())
DECLARE @dateTo		datetime2		= GETDATE()
DECLARE @topNrows	int				= 10
DECLARE @objectName nvarchar(257)	= NULL
DECLARE @queryId	int				= NULL
DECLARE @planId		int				= NULL
DECLARE @OrderBy	sysname			= 'total_cpu'

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 
SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @sqlstringdb	nvarchar(MAX) 
		, @countDBs		int = 1 
		, @numDBs		int 

DECLARE @databases table  
		( ID			int IDENTITY 
		, dbname		sysname NOT NULL) 

IF OBJECT_ID('tempdb..#intervals')	IS NOT NULL DROP TABLE #intervals
IF OBJECT_ID('tempdb..#waits')		IS NOT NULL DROP TABLE #waits
IF OBJECT_ID('tempdb..#totals')		IS NOT NULL DROP TABLE #totals
IF OBJECT_ID('tempdb..#output')		IS NOT NULL DROP TABLE #output

CREATE TABLE #intervals(
	[database_name]					sysname NULL
	, [runtime_stats_interval_id]	bigint	NULL
	, [start_time]					datetimeoffset NULL
	, [end_time]					datetimeoffset NULL)

CREATE TABLE #waits(
	[database_name]                         sysname NULL
    , [plan_id]								bigint	NULL
	, [avg_query_wait_time_ms]				float	NULL
	, [total_query_wait_time_ms]			bigint	NULL
	, [total_query_wait_time_ms_breakdown]	nvarchar(4000) NULL)

CREATE TABLE #totals(
	 [database_name]			sysname NULL
	, [total_executions]		bigint NULL
	, [total_duration]			float NULL
	, [total_cpu]				float NULL
	, [total_reads]				float NULL
	, [total_physical_reads]	float NULL
	, [total_writes]			float NULL
	, [total_memory]			float NULL
)

CREATE TABLE #output(
	[Id]									int IDENTITY NOT NULL
	, [database_name]						sysname	NULL
	, [start_time]							datetimeoffset NULL
	, [end_time]							datetimeoffset NULL
	, [query_id]							bigint	NULL
	, [plan_id]								bigint	NULL
	, [object_name]							sysname NULL
	, [total_executions]					bigint NULL
	, [total_duration_ms]					bigint NULL
	, [total_cpu_ms]						bigint NULL
	, [total_reads]							bigint NULL
	, [total_physical_reads]				bigint NULL
	, [total_writes]						bigint NULL
	, [total_memory]						bigint NULL
	, [total_query_wait_time_ms]			bigint NULL
	, [total_query_wait_time_ms_breakdown]	nvarchar(4000) NULL
	, [avg_duration_ms]						bigint NULL
	, [avg_cpu_time_ms]						bigint NULL
	, [avg_logical_io_reads]				bigint NULL
	, [avg_physical_io_reads]				bigint NULL
	, [avg_logical_io_writes]				bigint NULL
	, [avg_query_max_used_memory]			bigint NULL
	, [avg_query_wait_time_ms]				bigint NULL
	, [percentge_duration]					decimal(5,2) NULL
	, [percentge_cpu]						decimal(5,2) NULL
	, [percentge_reads]						decimal(5,2) NULL
	, [percentge_physical_reads]			decimal(5,2) NULL
	, [percentge_writes]					decimal(5,2) NULL
	, [percentge_memory]					decimal(5,2) NULL
	, [percentage_query_wait_time_ms]		decimal(5,2) NULL
	, [query_sql_text]						nvarchar(MAX) NULL
	, [query_plan]							nvarchar(MAX) NULL
)

SET @dateTo		= ISNULL(@dateTo, DATEADD(DAY, 7, @dateFrom)) -- one week
SET @topNrows	= ISNULL(@topNrows, 10)
SET @OrderBy	= ISNULL(@OrderBy, 'total_cpu')

-- Get everything if we want just an object
SET @topNrows	= CASE WHEN COALESCE(@objectName, CONVERT(varchar(30), @queryId), CONVERT(varchar(30), @planId)) 
                        IS NOT NULL THEN 2140000000 
                        ELSE @topNrows 
                    END

DECLARE @EngineEdition	int	= CONVERT(int, SERVERPROPERTY('EngineEdition'))
DECLARE @numericVersion int = CONVERT(int, PARSENAME(CONVERT(sysname, SERVERPROPERTY('ProductVersion')),4))

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

INSERT INTO @databases  
	SELECT TOP(100) PERCENT name  
		FROM sys.databases  
		WHERE is_query_store_on = 1
			AND name LIKE ISNULL(@dbname, name) 
		ORDER BY name ASC		 
SET @numDBs = @@ROWCOUNT 

IF @OrderBy NOT IN ('total_executions', 'avg_duration', 'avg_cpu', 'avg_reads', 'avg_physical_reads', 'avg_writes', 'avg_memory'
					, 'total_duration', 'total_cpu', 'total_reads', 'total_physical_reads', 'total_writes', 'total_memory') BEGIN 
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
	GOTO OnError
END

-- Get all the intervals within the DateFrom and DateTo specified
DECLARE @sql nvarchar(MAX) = 'USE [?]
	SELECT DB_NAME()
			, runtime_stats_interval_id
			, start_time
			, end_time
		FROM sys.query_store_runtime_stats_interval
		WHERE start_time <= @dateTo
			AND end_time >= @dateFrom'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

	INSERT INTO #intervals ([database_name], [runtime_stats_interval_id], [start_time], [end_time])
	EXECUTE sys.sp_executesql 
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

IF @numericVersion > 13 BEGIN
	WHILE @countDBs <= @numDBs BEGIN 
        SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDBs)
		SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

        INSERT INTO #waits (database_name, plan_id, [avg_query_wait_time_ms], total_query_wait_time_ms, total_query_wait_time_ms_breakdown)
	    EXECUTE sys.sp_executesql @sqlstmt = @sqlstringdb
        
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
		, SUM(rst.count_executions * rst.avg_physical_io_reads) AS total_physical_reads
		, SUM(rst.count_executions * rst.avg_logical_io_writes) AS total_writes
		, SUM(rst.count_executions * rst.avg_query_max_used_memory) AS total_memory
	FROM sys.query_store_runtime_stats AS rst
	INNER JOIN #intervals AS rsti
		ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id
			AND rsti.database_name = DB_NAME() COLLATE DATABASE_DEFAULT'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

    INSERT INTO #totals([database_name], [total_executions], [total_duration], [total_cpu], [total_reads], [total_physical_reads], [total_writes], [total_memory])
	EXECUTE sys.sp_executesql @sqlstmt = @sqlstringdb
        
    SET @countDBs = @countDBs + 1;
END;
SET @countDBs = 1; -- Reset for next loops

--SELECT * FROM #totals

-- Get the final output for the period defined.
SET @sql = 'USE [?]

-- Get some data before for performance
DECLARE @objectId int = OBJECT_ID(@objectName)

-- object name is not correct
IF @objectId IS NULL AND @objectName IS NOT NULL BEGIN
	RAISERROR (''@object_name does not exist, please double check and run again'', 16, 1, 1) WITH NOWAIT;
	RETURN;
END;

SELECT TOP (@topNrows) 
		CONVERT(DATETIME2(0), MIN(rsti.start_time)) AS start_time
		, CONVERT(DATETIME2(0), MAX(rsti.end_time)) AS end_time
		, rst.plan_id
		, q.query_id
		, q.query_text_id
		, q.object_id
		, SUM(rst.count_executions) AS total_executions
		-- averages
		, AVG(rst.avg_duration) AS avg_duration		   
		, AVG(rst.avg_cpu_time) AS avg_cpu_time		   
		, AVG(rst.avg_logical_io_reads) AS avg_logical_io_reads 
		, AVG(rst.avg_physical_io_reads) AS avg_physical_io_reads 
		, AVG(rst.avg_logical_io_writes) AS avg_logical_io_writes
		, AVG(rst.avg_query_max_used_memory) AS avg_query_max_used_memory
		-- totals
		, SUM(rst.count_executions * rst.avg_duration)			AS total_duration
		, SUM(rst.count_executions * rst.avg_cpu_time)			AS total_cpu
		, SUM(rst.count_executions * rst.avg_logical_io_reads)	AS total_reads
		, SUM(rst.count_executions * rst.avg_physical_io_reads)	AS total_physical_reads
		, SUM(rst.count_executions * rst.avg_logical_io_writes) AS total_writes
		, SUM(rst.count_executions * rst.avg_query_max_used_memory) AS total_memory
		--, 		* 
INTO #t
	FROM sys.query_store_runtime_stats AS rst
		INNER JOIN sys.query_store_plan AS qp
			ON qp.plan_id = rst.plan_id
		INNER JOIN sys.query_store_query AS q
			ON q.query_id = qp.query_id
		INNER JOIN #intervals AS rsti
			ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id 
				AND rsti.database_name = DB_NAME() COLLATE DATABASE_DEFAULT
	WHERE (@objectId	IS NULL OR q.object_id = @objectId) 
		AND (@queryId	IS NULL OR q.query_id = @queryId)
		AND (@planId	IS NULL OR rst.plan_id = @planId)
	GROUP BY rst.plan_id
			, q.query_id
			, q.query_text_id
			, q.object_id
			, CASE WHEN COALESCE(@objectId,@queryId,@planId) IS NULL THEN NULL ELSE rsti.runtime_stats_interval_id END
	ORDER BY  CASE WHEN COALESCE(@objectId,@queryId,@planId) IS NULL THEN NULL ELSE rsti.runtime_stats_interval_id END
			, CASE WHEN @OrderBy = ''total_executions''		COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_duration''			COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_duration) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_cpu_time''			COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_cpu_time) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_reads''			COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_logical_io_reads) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_physical_reads''	COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_physical_io_reads) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_writes''			COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_logical_io_writes) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_memory''			COLLATE DATABASE_DEFAULT	THEN AVG(rst.avg_query_max_used_memory) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_duration''		COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_duration) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_cpu''			COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_cpu_time) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_reads''			COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_logical_io_reads) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_physical_reads''	COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_physical_io_reads) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_writes''			COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_logical_io_writes) ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_memory''			COLLATE DATABASE_DEFAULT	THEN SUM(rst.count_executions * rst.avg_query_max_used_memory) ELSE NULL END DESC

SELECT DB_NAME() AS database_name
		, rst.start_time
		, rst.end_time
		, qp.query_id
		, rst.plan_id
		, ISNULL(OBJECT_SCHEMA_NAME(rst.object_id) + ''.'' + OBJECT_NAME(rst.object_id), ''-'') AS object_name
		, rst.total_executions
	
	-- totals
		, CONVERT(BIGINT, rst.total_duration / 1000)	AS total_duration_ms
		, CONVERT(BIGINT, rst.total_cpu / 1000)		AS total_cpu_ms
		, rst.total_reads
		, rst.total_physical_reads
		, rst.total_writes
		, rst.total_memory
		, ISNULL(w.total_query_wait_time_ms					, 0) AS total_query_wait_time_ms			 
		, ISNULL(w.total_query_wait_time_ms_breakdown		, ''-'') AS total_query_wait_time_ms_breakdown

	-- averages
		, ISNULL(CONVERT(BIGINT, rst.avg_duration / 1000		), 0) AS avg_duration_ms
		, ISNULL(CONVERT(BIGINT, rst.avg_cpu_time / 1000		), 0) AS avg_cpu_time_ms
		, ISNULL(CONVERT(BIGINT, rst.avg_logical_io_reads		), 0) AS avg_logical_io_reads
		, ISNULL(CONVERT(BIGINT, rst.avg_physical_io_reads		), 0) AS avg_physical_io_reads
		, ISNULL(CONVERT(BIGINT, rst.avg_logical_io_writes		), 0) AS avg_logical_io_writes
		, ISNULL(CONVERT(BIGINT, rst.avg_query_max_used_memory	), 0) AS avg_query_max_used_memory
		, ISNULL(CONVERT(BIGINT, w.avg_query_wait_time_ms		), 0) AS avg_query_wait_time_ms

	-- percentages 
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_duration		* 100 / NULLIF(t.total_duration, 0)		), 0)	AS percentge_duration
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_cpu			* 100 / NULLIF(t.total_cpu, 0)			), 0)	AS percentge_cpu
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_reads			* 100 / NULLIF(t.total_reads, 0)		), 0)	AS percentge_reads
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_physical_reads	* 100 / NULLIF(t.total_physical_reads, 0)), 0)	AS percentge_physical_reads
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_writes			* 100 / NULLIF(t.total_writes, 0)		), 0)	AS percentge_writes
		, ISNULL(CONVERT(DECIMAL(5,2), rst.total_memory			* 100 / NULLIF(t.total_memory, 0)		), 0)	AS percentge_memory
		, ISNULL(CONVERT(DECIMAL(5,2), w.total_query_wait_time_ms * 100. / NULLIF(tw.total_query_wait_time_ms, 0)), 0) AS percentage_query_wait_time_ms

	-- Query Text and Plan 
		, qt.query_sql_text
		, qp.query_plan
		--, ISNULL(TRY_CONVERT(XML, ''<!--'' + REPLACE(qt.query_sql_text, ''--'', ''/* this line was commented out */'') + ''-->''), qt.query_sql_text) AS query_sql_text
		--, ISNULL(TRY_CONVERT(XML, qp.query_plan), qp.query_plan) AS query_plan

	FROM #t AS rst
		INNER JOIN sys.query_store_plan AS qp
			ON qp.plan_id = rst.plan_id
		INNER JOIN sys.query_store_query_text AS qt
			ON qt.query_text_id = rst.query_text_id 
		LEFT JOIN #waits AS w
			ON w.plan_id = qp.plan_id
				AND w.database_name = DB_NAME() COLLATE DATABASE_DEFAULT
		OUTER APPLY (SELECT * FROM #totals WHERE #totals.database_name = DB_NAME() COLLATE DATABASE_DEFAULT) AS t
		OUTER APPLY (SELECT SUM(total_query_wait_time_ms) AS total_query_wait_time_ms FROM #waits WHERE #waits.database_name = DB_NAME() COLLATE DATABASE_DEFAULT) AS tw
	ORDER BY  CASE WHEN COALESCE(@objectId,@queryId,@planId) IS NULL THEN NULL ELSE rst.start_time END
			, CASE WHEN @OrderBy = ''total_executions''	COLLATE DATABASE_DEFAULT THEN rst.total_executions ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_duration''		COLLATE DATABASE_DEFAULT THEN rst.avg_duration ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_cpu''			COLLATE DATABASE_DEFAULT THEN rst.avg_cpu_time ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_reads''		COLLATE DATABASE_DEFAULT THEN rst.avg_logical_io_reads ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''avg_writes''		COLLATE DATABASE_DEFAULT THEN rst.avg_logical_io_writes ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_duration''	COLLATE DATABASE_DEFAULT THEN rst.total_duration	ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_cpu''		COLLATE DATABASE_DEFAULT THEN rst.total_cpu ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_reads''		COLLATE DATABASE_DEFAULT THEN rst.total_reads ELSE NULL END DESC
			, CASE WHEN @OrderBy = ''total_writes''		COLLATE DATABASE_DEFAULT THEN rst.total_writes ELSE NULL END DESC
'

WHILE @countDBs <= @numDBs BEGIN 
    SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDBs)
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname)

	INSERT INTO #output ([database_name], [start_time], [end_time], [query_id], [plan_id], [object_name]
						, [total_executions], [total_duration_ms], [total_cpu_ms], [total_reads], [total_physical_reads], [total_writes], [total_memory], [total_query_wait_time_ms], [total_query_wait_time_ms_breakdown]
						, [avg_duration_ms], [avg_cpu_time_ms], [avg_logical_io_reads], [avg_physical_io_reads], [avg_logical_io_writes], [avg_query_max_used_memory], [avg_query_wait_time_ms]
						, [percentge_duration], [percentge_cpu], [percentge_reads], [percentge_physical_reads], [percentge_writes], [percentge_memory], [percentage_query_wait_time_ms]
						, [query_sql_text], [query_plan])
	EXECUTE sys.sp_executesql 
		@sqlstmt		= @sqlstringdb
		, @params		= N'@topNrows INT, @OrderBy SYSNAME, @objectName NVARCHAR(257), @queryId INT, @planId INT'
		, @topNrows		= @topNrows 
		, @OrderBy		= @OrderBy
		, @objectName	= @objectName
		, @queryId		= @queryId
		, @planId		= @planId
        
    SET @countDBs = @countDBs + 1;
END;

SELECT [database_name]
		, CONVERT(smalldatetime, [start_time]) AS [start_time]
		, CONVERT(smalldatetime, [end_time]	 ) AS [end_time]	
		, [query_id]
		, [plan_id]
		, [object_name]
		, [total_executions]
		, [avg_duration_ms]
		, [avg_cpu_time_ms]
		, [avg_logical_io_reads]
		, CONVERT(decimal(15,2), [avg_logical_io_reads]		/ 128.) AS [avg_mb_read]
		, [avg_physical_io_reads]
		, CONVERT(decimal(15,2), [avg_physical_io_reads]	/ 128.) AS [avg_physical_mb_read]
		, [avg_logical_io_writes]
		, CONVERT(decimal(15,2), [avg_logical_io_writes]	/ 128.) AS [avg_mb_written]
		, [avg_query_max_used_memory]
		, CONVERT(decimal(15,2), [avg_query_max_used_memory]/ 128.) AS [avg_mb_memory]
		, [avg_query_wait_time_ms]
		, [total_duration_ms]
		, [total_cpu_ms]
		, [total_reads]
		, CONVERT(decimal(15,2), [total_reads]	/ 128.				) AS [total_mb_read]
		, CONVERT(decimal(15,2), [total_reads]	/ 128. / 1024		) AS [total_gb_read]
		, CONVERT(decimal(15,2), [total_reads]	/ 128. / 1024 / 1024) AS [total_tb_read]
		, [total_physical_reads]
		, CONVERT(decimal(15,2), [total_physical_reads]	/ 128.)					AS [total_physical_mb_read]
		, CONVERT(decimal(15,2), [total_physical_reads]	/ 128. / 1024)			AS [total_physical_gb_read]
		, CONVERT(decimal(15,2), [total_physical_reads]	/ 128. / 1024 / 1024)	AS [total_physical_tb_read]
		, [total_writes]
		, [total_memory]
		, CONVERT(decimal(15,2), [total_memory]	/ 128.) AS [total_mb_memory]
		, [total_query_wait_time_ms]
		, [total_query_wait_time_ms_breakdown]
		, [percentge_duration]
		, [percentge_cpu]
		, [percentge_reads]
		, [percentge_physical_reads]
		, [percentge_writes]
		, [percentge_memory]
		, [percentage_query_wait_time_ms]
		, ISNULL(TRY_CONVERT(xml, '<!--' + REPLACE(query_sql_text, '--', '/* this line was commented out */') + '-->'), query_sql_text) AS query_sql_text
		, ISNULL(TRY_CONVERT(xml, query_plan), query_plan) AS query_plan
FROM #output
ORDER BY [Id]

OnError:
GO