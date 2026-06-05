SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
/*
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
--				- @object_name 
--				- @query_id	
--				- @plan_id	
--				- @OrderBy	
--
-- Log History:	
--				11/11/2019  RAG - Created
--				18/11/2019  RAG - Added average wait times per wait type
--				24/01/2021  RAG - Added functionality to go through all databaes
--				05/03/2021  RAG - Added parameter @object_name, which will accept values in the format "schema.object_name" 
--				26/03/2021  RAG - Changes:
--									- Added parameter @query_id, to display only one query
--									- Added parameter @plan_id, to display only one plan
--									- Changed values for sorting on averages to simplify
--				30/03/2021  RAG - Changes in the behaviour:
--									- When passing either @object_name, @query_id or @plan_id, it will display data per interval so 
--										you can see how the query is performing through the selected period
--				13/04/2021  RAG - @object_id will be calculated from @object_name in advance
--				29/04/2021  RAG - Changes:
--									- Fixed bug when sorting if object/query/plan was passed
--									- Return interval in SMALLDATETIME
--				11/06/2021  RAG - Changes:
--                                  - Added physical reads
--				01/12/2021	RAG	- Changes
--									- Changed some column names to match others (avg)
--									- Added validation in case object does not exist
--				01/03/2022	RAG	- Changes
--									- variable names to lower case and _
--									- fix wait stats as currently were always aggregated per query_plan_id, even when output was aggregated by interval
--										due to one of the params @object_name, @query_id, @plan_id being passed to the script
--				01/04/2022	RAG	- Changes
--									- Added avg_rowcount and total_rowcount
--				17/10/2022	RAG	- Changes
--									- Changed some parts to dynamic SQL for performance
--				28/11/2022	RAG	- Changes
--									- Added total_cpu_hhmmss and total_duration_hhmmss in human readable time format
--				06/08/2022	RAG	- Changes
--									- Added dynamic parts to the query that get waits to filter by plan_id, query_id and object_name
--				02/03/2023	RAG	- Changes
--									- Added columns 
--										- [total_exec_successful]
--										- [total_exec_aborted]
--										- [total_exec_exceptions]
--										- [total_executions_breakdown]
--				19/07/2023	RAG	- Added [query_hash] column and @query_hash parameter
--				12/08/2025	RAG	- Changes
--									- Added @GroupBy to see stats by different angles
--										- plan_id, previous behavior TOP(x) plans order by @OrderBy
--										- query_id, TOP(x) queries order by @OrderBy, multiple plans can happen, 
--												one displayed but not necessarily the "bad" one
--										- query_hash, TOP(x) query hashes by @OrderBy, multiple query ids / plans can happen, 
--												one displayed but not necessarily the "bad" one
--									- Refactoring 
--										- Simplified queries that stage data to improve performance
--
-- SELECT * FROM sys.databases WHERE is_query_store_on = 1 ORDER BY name
-- =============================================
*/

DECLARE @dbname	    sysname			= 'dbname';
DECLARE @dateFrom	datetime2		= DATEADD(DAY, -7, GETUTCDATE());
DECLARE @dateTo		datetime2		= GETUTCDATE();
DECLARE @topNrows	int				= 10;
DECLARE @object_name nvarchar(261)	= NULL;
DECLARE @query_id	int				= NULL;
DECLARE @plan_id	int				= NULL;
DECLARE @query_hash	binary(8)		= NULL;
DECLARE @GroupBy	nvarchar(60)	= 'plan_id'; /* plan_id (default), query_id, query_hash */
DECLARE @OrderBy	sysname			= 'total_cpu';

/*
--============================================= 
-- Do not modify below this line
-- unless you know what you are doing!!
--============================================= 
*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @sqlstringdb	nvarchar(MAX) 
		, @countDBs		int = 1 
		, @numDBs		int 
		, @whereclause  nvarchar(MAX) = ''
		, @orderclause  nvarchar(MAX) = '';

DECLARE @databases table  
		( ID			int IDENTITY 
		, dbname		sysname NOT NULL); 

DECLARE @startDateTime datetime = GETUTCDATE();

DROP TABLE IF EXISTS #intervals;
DROP TABLE IF EXISTS #waits;
DROP TABLE IF EXISTS #total_exec;
DROP TABLE IF EXISTS #totals;
DROP TABLE IF EXISTS #output;

CREATE TABLE #intervals(
	[database_id]					int NULL
	, [runtime_stats_interval_id]	bigint	NULL
	, [start_time]					datetimeoffset NULL
	, [end_time]					datetimeoffset NULL);

CREATE TABLE #waits(
	[database_id]							int NULL
	, [GroupBy]								binary(8) NULL /* this can be either plan_id, query_id or query_hash, later will be converted back to numeric if plan_id or query_id */
	, [runtime_stats_interval_id]			bigint	NULL
	, [avg_query_wait_time_ms]				float	NULL
	, [total_query_wait_time_ms]			bigint	NULL
	, [total_query_wait_time_ms_breakdown]	nvarchar(4000) NULL);

CREATE TABLE #total_exec(
	[database_id]					smallint		NULL
	, [GroupBy]						binary(8)		NULL
	, [start_time]					datetime2(0)	NULL
	, [end_time]					datetime2(0)	NULL
	, [runtime_stats_interval_id]	bigint			NULL
	, [plan_id]						bigint			NULL
	, [query_id]					bigint			NULL
	, [query_hash]					binary(8)		NULL
	, [total_executions]			bigint			NULL
	, [total_exec_successful]		bigint			NULL
	, [total_exec_aborted]			bigint			NULL
	, [total_exec_exceptions]		bigint			NULL
	, [avg_duration]				float(8)		NULL
	, [avg_cpu_time]				float(8)		NULL
	, [avg_logical_io_reads]		float(8)		NULL
	, [avg_physical_io_reads]		float(8)		NULL
	, [avg_logical_io_writes]		float(8)		NULL
	, [avg_query_max_used_memory]	float(8)		NULL
	, [avg_rowcount]				float(8)		NULL
);

CREATE TABLE #totals(
	[database_id]				int NULL
	, [total_executions]		bigint NULL
	, [total_duration]			float NULL
	, [total_cpu]				float NULL
	, [total_reads]				float NULL
	, [total_physical_reads]	float NULL
	, [total_writes]			float NULL
	, [total_memory]			float NULL
	, [total_query_wait_time_ms]float NULL
);

CREATE TABLE #output(
	[Id]									int IDENTITY NOT NULL
	, [database_name]						sysname	NULL
	, [start_time]							datetimeoffset NULL
	, [end_time]							datetimeoffset NULL
	, [query_id]							bigint	NULL
	, [plan_id]								bigint	NULL
	, [query_hash]							binary(8) NULL
	, [object_name]							sysname NULL
	, [total_executions]					bigint NULL
	, [total_exec_successful]				bigint NULL
	, [total_exec_aborted]					bigint NULL
	, [total_exec_exceptions]				bigint NULL
	, [total_duration_ms]					bigint NULL
	, [total_cpu_time_ms]					bigint NULL
	, [total_logical_io_reads]				bigint NULL
	, [total_physical_io_reads]				bigint NULL
	, [total_writes]						bigint NULL
	, [total_memory]						bigint NULL
	, [total_rowcount]						bigint NULL
	, [total_query_wait_time_ms]			bigint NULL
	, [total_query_wait_time_ms_breakdown]	nvarchar(4000) NULL
	, [avg_duration_ms]						bigint NULL
	, [avg_cpu_time_ms]						bigint NULL
	, [avg_logical_io_reads]				bigint NULL
	, [avg_physical_io_reads]				bigint NULL
	, [avg_logical_io_writes]				bigint NULL
	, [avg_query_max_used_memory]			bigint NULL
	, [avg_rowcount]						bigint NULL
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
);

SET @dateFrom	= ISNULL(@dateFrom, DATEADD(DAY, 7, GETUTCDATE())); /* one week ago */
SET @dateTo		= ISNULL(@dateTo, GETUTCDATE()); /* till now */
SET @topNrows	= ISNULL(@topNrows, 10);
SET @GroupBy	= ISNULL(@GroupBy, 'plan_id');
SET @OrderBy	= ISNULL(@OrderBy, 'total_cpu');

/* Get everything if we want just an object */
SET @topNrows	= CASE WHEN COALESCE(@object_name, CONVERT(nvarchar(261), @query_id), CONVERT(nvarchar(261), @query_hash), CONVERT(nvarchar(261), @plan_id)) IS NOT NULL 
						THEN 2140000000 
						ELSE @topNrows 
					END;

DECLARE @EngineEdition	int	= CONVERT(int, SERVERPROPERTY('EngineEdition'));
DECLARE @numericVersion int = CONVERT(int, PARSENAME(CONVERT(sysname, SERVERPROPERTY('ProductVersion')),4));

IF @EngineEdition = 5 BEGIN
/* Azure SQL Database, the script can't run on multiple databases */
	SET @dbname	= DB_NAME();
END;

INSERT INTO @databases
	SELECT TOP (100) PERCENT name
		FROM sys.databases
		WHERE is_query_store_on = 1
			AND name LIKE ISNULL(@dbname, name)
		ORDER BY name ASC;	 
SET @numDBs = @@ROWCOUNT; 

IF COALESCE(@object_name, CONVERT(nvarchar(261), @query_id), CONVERT(nvarchar(261), @query_hash), CONVERT(nvarchar(261), @plan_id)) IS NOT NULL
BEGIN 
	SET @GroupBy = 'plan_id';
END

IF @GroupBy NOT IN ('plan_id', 'query_id', 'query_hash') BEGIN 
	RAISERROR ('The possible values for @OrderBy are the following:
- plan_id
- query_id
- query_hash

Please Choose on of them and run it again', 16, 0) WITH NOWAIT;
	/*GOTO OnError;*/
END;

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
	/*GOTO OnError;*/
END;

/*
-- Get all the intervals within the DateFrom and DateTo specified
*/
DECLARE @sql nvarchar(MAX) = 'USE [?]
	SELECT DB_ID()
			, runtime_stats_interval_id
			, start_time
			, end_time
		FROM sys.query_store_runtime_stats_interval
		WHERE start_time <= @dateTo
			AND end_time >= @dateFrom';

WHILE @countDBs <= @numDBs BEGIN 
	SELECT @dbname = dbname FROM @databases WHERE ID = @countDBs;
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

	INSERT INTO #intervals ([database_id], [runtime_stats_interval_id], [start_time], [end_time])
	EXECUTE sys.sp_executesql 
		@sqlstmt	= @sqlstringdb
		, @params	= N'@dateFrom DATETIME2, @dateTo DATETIME2'
		, @dateFrom = @dateFrom 
		, @dateTo	= @dateTo;
		
	SET @countDBs = @countDBs + 1;
END;
SET @countDBs = 1; /* Reset for next loops */

PRINT 'Intervals retrieved in ' + CONVERT(varchar(30), DATEDIFF(MILLISECOND, @startDateTime, GETUTCDATE())) + ' milliseconds';
SET @startDateTime = GETUTCDATE();

/* 
SELECT * FROM #intervals 
--*/

/*
 Wait Stats (if 2017 or higher) for the period defined, grouped by GroupBy
*/
SET @sql = 'USE [?]

DECLARE @object_id int = OBJECT_ID(@object_name)

/* object name is not correct */
IF @object_id IS NULL AND @object_name IS NOT NULL BEGIN
	RAISERROR (''@object_name does not exist, please double check and run again'', 16, 1, 1) WITH NOWAIT;
	RETURN;
END;

DROP TABLE IF EXISTS #w;

SELECT w.plan_id,
	   w.wait_category_desc,
	   w.total_query_wait_time_ms,
	   w.avg_query_wait_time_ms,
	   rsti.runtime_stats_interval_id
INTO #w
	FROM sys.query_store_wait_stats AS w
		INNER JOIN #intervals AS rsti
			ON rsti.runtime_stats_interval_id = w.runtime_stats_interval_id
				AND rsti.database_id = DB_ID()

SELECT DB_ID() AS database_id,
	w.GroupBy,
	w.runtime_stats_interval_id,
	AVG(w.avg_query_wait_time_ms) AS avg_query_wait_time_ms,
	SUM(w.total_query_wait_time_ms) AS total_query_wait_time_ms,
	STRING_AGG(w.wait_category_desc + '' (Total: '' + CONVERT(varchar(30), w.total_query_wait_time_ms) + '' - Avg: ''
					+ CONVERT(varchar(30), w.avg_query_wait_time_ms) + '')'',
					'', '') WITHIN GROUP (ORDER BY w.total_query_wait_time_ms DESC) AS total_query_wait_time_ms_breakdown
	FROM (
	SELECT CASE 
				WHEN @GroupBy = ''query_hash'' COLLATE DATABASE_DEFAULT THEN q.query_hash
				WHEN @GroupBy = ''plan_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), w.plan_id)
				WHEN @GroupBy = ''query_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), q.query_id)
			END AS GroupBy,
		CASE WHEN COALESCE(@object_id, @plan_id, @query_id, @query_hash) IS NULL THEN NULL ELSE w.runtime_stats_interval_id END AS runtime_stats_interval_id,
		w.wait_category_desc,
		AVG(w.avg_query_wait_time_ms) AS avg_query_wait_time_ms,
		SUM(w.total_query_wait_time_ms) AS total_query_wait_time_ms
	FROM #w AS w
		INNER JOIN sys.query_store_plan AS qp
			ON qp.plan_id = w.plan_id
		INNER JOIN sys.query_store_query AS q
			ON q.query_id = qp.query_id
	WHERE 1=1 
		[WHERECLAUSE]	

	GROUP BY CASE 
				WHEN @GroupBy = ''query_hash'' COLLATE DATABASE_DEFAULT THEN q.query_hash
				WHEN @GroupBy = ''plan_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), w.plan_id)
				WHEN @GroupBy = ''query_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), q.query_id)
			END,
			CASE WHEN COALESCE(@object_id, @plan_id, @query_id, @query_hash) IS NULL THEN NULL ELSE w.runtime_stats_interval_id END,
			w.wait_category_desc
	) AS w
GROUP BY w.GroupBy,
		w.runtime_stats_interval_id;
';

IF @numericVersion > 13 BEGIN
	WHILE @countDBs <= @numDBs BEGIN 
		SELECT @dbname = dbname FROM @databases WHERE ID = @countDBs;
		SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

		SET @whereclause = '';
		SET @orderclause = '';
	
		SET @sqlstringdb = REPLACE(@sql, '?', @dbname);
	
		/* WHERE clause */
		IF @query_id IS NOT NULL 
		BEGIN
			SET @whereclause += CHAR(10) + 'AND qp.query_id = @query_id';
		END;
		IF @plan_id IS NOT NULL 
		BEGIN
			SET @whereclause += CHAR(10) + 'AND w.plan_id = @plan_id';
		END;
		IF @object_name IS NOT NULL 
		BEGIN
			SET @whereclause += CHAR(10) + 'AND q.object_id = OBJECT_ID(@object_name)';
		END;
		IF @query_hash IS NOT NULL 
		BEGIN
			SET @whereclause += CHAR(10) + 'AND q.query_hash = @query_hash';
		END;

		SET @sqlstringdb = REPLACE(@sqlstringdb, '[WHERECLAUSE]', @whereclause);

		/* 
		SELECT @sqlstringdb 
		--*/

		INSERT INTO #waits (database_id, GroupBy, runtime_stats_interval_id, [avg_query_wait_time_ms], total_query_wait_time_ms, total_query_wait_time_ms_breakdown)
		EXECUTE sys.sp_executesql @sqlstmt = @sqlstringdb
			, @params		= N'@object_name nvarchar(261), @plan_id int, @query_id int, @query_hash binary(8), @GroupBy nvarchar(60)'
			, @object_name	= @object_name
			, @plan_id		= @plan_id
			, @query_id		= @query_id
			, @query_hash	= @query_hash
			, @GroupBy		= @GroupBy;
		SET @countDBs = @countDBs + 1;
	END;
END;
ELSE BEGIN
	INSERT INTO #waits (database_id, GroupBy, [avg_query_wait_time_ms], total_query_wait_time_ms, total_query_wait_time_ms_breakdown)
	VALUES (0, 0x0, 0, 0, N'n/a');
END;
SET @countDBs = 1; /* Reset for next loops */

PRINT 'Waits retrieved in ' + CONVERT(varchar(30), DATEDIFF(MILLISECOND, @startDateTime, GETUTCDATE())) + ' milliseconds';
SET @startDateTime = GETUTCDATE();

/* 
SELECT * FROM #waits 
--*/

/*
-- Get the total executions for the period defined, grouped by GroupBy
*/
SET @sql = 'USE [?]

/* Get some data before for performance */
DECLARE @object_id int = OBJECT_ID(@object_name)

/* object name is not correct */
IF @object_id IS NULL AND @object_name IS NOT NULL BEGIN
	RAISERROR (''@object_name does not exist, please double check and run again'', 16, 1, 1) WITH NOWAIT;
	RETURN;
END;

DROP TABLE IF EXISTS #db_total_execs
DROP TABLE IF EXISTS #db_avg_execs

SELECT qp.plan_id,
	   qp.query_id,
	   q.query_hash,
	   q.object_id
INTO #db_plan_query
FROM sys.query_store_plan AS qp
	INNER JOIN sys.query_store_query AS q
		ON q.query_id = qp.query_id;

CREATE CLUSTERED INDEX #CIX ON #db_plan_query (plan_id)

-------------------------------
-- total execution counts per plan per interval
-------------------------------
SELECT DB_ID() AS database_id,
		start_time,
		end_time,
		runtime_stats_interval_id,
		plan_id,
		ISNULL(Regular, 0) + ISNULL(Aborted, 0) + ISNULL(Exception, 0) AS total_executions,		
		ISNULL(Regular, 0) AS total_exec_successful,
		ISNULL(Aborted, 0) AS total_exec_aborted,
		ISNULL(Exception, 0) AS total_exec_exceptions
INTO #db_total_execs
FROM (
	SELECT 	rst.runtime_stats_interval_id,
			rst.plan_id,
			CONVERT(datetime2(0), MIN(rsti.start_time)) AS start_time,
			CONVERT(datetime2(0), MAX(rsti.end_time)) AS end_time,
			rst.execution_type_desc,
			SUM(rst.count_executions) AS count_executions
	FROM sys.query_store_runtime_stats AS rst
		INNER JOIN #intervals AS rsti
			ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id
				AND rsti.database_id = DB_ID()
	--WHERE 1=1 

	
	GROUP BY rst.runtime_stats_interval_id,
			rst.plan_id,
			rst.execution_type_desc
) AS t
PIVOT (
	MAX(count_executions)
	FOR execution_type_desc IN ([Regular], [Aborted], [Exception])
) AS pvt;

--
-- Averages per plan per interval
--
SELECT DB_ID() AS database_id,
		rst.runtime_stats_interval_id,
		rsti.start_time,
		rsti.end_time,
		rst.plan_id,
			
		/* we need to recalculate the total average since each line will have its own execution count 
			and doing AVG of the avg_ columns will end up with incorrect results 
		*/
		SUM(rst.avg_duration * rst.count_executions)				/ SUM(rst.count_executions) AS avg_duration,
		SUM(rst.avg_cpu_time * rst.count_executions)				/ SUM(rst.count_executions) AS avg_cpu_time,		   
		SUM(rst.avg_logical_io_reads * rst.count_executions)		/ SUM(rst.count_executions) AS avg_logical_io_reads,
		SUM(rst.avg_physical_io_reads * rst.count_executions)		/ SUM(rst.count_executions) AS avg_physical_io_reads,
		SUM(rst.avg_logical_io_writes * rst.count_executions)		/ SUM(rst.count_executions) AS avg_logical_io_writes,
		SUM(rst.avg_query_max_used_memory * rst.count_executions)	/ SUM(rst.count_executions) AS avg_query_max_used_memory,
		SUM(rst.avg_rowcount * rst.count_executions)				/ SUM(rst.count_executions) AS avg_rowcount
INTO #db_avg_execs
FROM sys.query_store_runtime_stats AS rst
	INNER JOIN #intervals AS rsti
		ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id
			AND rsti.database_id = DB_ID()
--WHERE 1=1 

GROUP BY rst.runtime_stats_interval_id,
		rsti.start_time,
		rsti.end_time,
		rst.plan_id


-- Put together the totals with the averages
SELECT t.database_id,
	   CASE
		   WHEN @GroupBy = ''query_hash'' COLLATE DATABASE_DEFAULT THEN qp.query_hash
		   WHEN @GroupBy = ''plan_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), qp.plan_id)
		   WHEN @GroupBy = ''query_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), qp.query_id)
	   END AS GroupBy,
	   CONVERT(datetime2(0), MIN(t.start_time)) AS start_time,
	   CONVERT(datetime2(0), MAX(t.end_time)) AS end_time,
	   CASE
		   WHEN COALESCE(@object_id, @plan_id, @query_id, @query_hash) IS NULL THEN NULL
		   ELSE t.runtime_stats_interval_id
	   END AS runtime_stats_interval_id,
	   MAX(qp.plan_id) AS plan_id,
	   MAX(qp.query_id) AS query_id,
	   MAX(qp.query_hash) AS query_hash,
	   SUM(t.total_executions) AS total_executions,
	   SUM(t.total_exec_successful) AS total_exec_successful,
	   SUM(t.total_exec_aborted) AS total_exec_aborted,
	   SUM(t.total_exec_exceptions) total_exec_exceptions,

	   /* 
			we need to recalculate the total average since each line will have its own execution count 
			and doing AVG of the avg_ columns will end up with incorrect results 
		*/
	   SUM(a.avg_duration * t.total_executions)					/ SUM(t.total_executions) AS avg_duration,
	   SUM(a.avg_cpu_time * t.total_executions)					/ SUM(t.total_executions) AS avg_cpu_time,
	   SUM(a.avg_logical_io_reads * t.total_executions)			/ SUM(t.total_executions) AS avg_logical_io_reads,
	   SUM(a.avg_physical_io_reads * t.total_executions)		/ SUM(t.total_executions) AS avg_physical_io_reads,
	   SUM(a.avg_logical_io_writes * t.total_executions)		/ SUM(t.total_executions) AS avg_logical_io_writes,
	   SUM(a.avg_query_max_used_memory * t.total_executions)	/ SUM(t.total_executions) AS avg_query_max_used_memory,
	   SUM(a.avg_rowcount * t.total_executions)					/ SUM(t.total_executions) AS avg_rowcount
FROM #db_total_execs AS t
	INNER JOIN #db_avg_execs AS a
		ON a.database_id = t.database_id
			AND a.runtime_stats_interval_id = t.runtime_stats_interval_id
			AND a.plan_id = t.plan_id
	INNER JOIN #db_plan_query AS qp
		ON qp.plan_id = t.plan_id
WHERE 1=1 
	[WHERECLAUSE]	

GROUP BY t.database_id,
		 CASE
			 WHEN @GroupBy = ''query_hash'' COLLATE DATABASE_DEFAULT THEN qp.query_hash
			 WHEN @GroupBy = ''plan_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), qp.plan_id)
			 WHEN @GroupBy = ''query_id'' COLLATE DATABASE_DEFAULT THEN CONVERT(binary(8), qp.query_id)
		 END,
		 CASE
			 WHEN COALESCE(@object_id, @plan_id, @query_id, @query_hash) IS NULL THEN NULL
			 ELSE t.runtime_stats_interval_id
		 END;

';

WHILE @countDBs <= @numDBs BEGIN 
	SELECT @dbname = dbname FROM @databases WHERE ID = @countDBs;
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

	SET @whereclause = '';
	SET @orderclause = '';
	
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

	/* [WHERECLAUSE] */
	IF @query_id IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND qp.query_id = @query_id';
	END;
	IF @plan_id IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND qp.plan_id = @plan_id';
	END;
	IF @object_name IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND qp.object_id = OBJECT_ID(@object_name)';
	END;
	IF @query_hash IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND qp.query_hash = @query_hash';
	END;

	SET @sqlstringdb = REPLACE(@sqlstringdb, '[WHERECLAUSE]', @whereclause);

	/* 
	SELECT @sqlstringdb 
	--*/

	INSERT INTO #total_exec ([database_id], [GroupBy], [start_time], [end_time], [runtime_stats_interval_id], [plan_id], [query_id], [query_hash], 
							[total_executions], [total_exec_successful],  [total_exec_aborted], [total_exec_exceptions], [avg_duration], [avg_cpu_time], 
							[avg_logical_io_reads], [avg_physical_io_reads], [avg_logical_io_writes], [avg_query_max_used_memory], [avg_rowcount])
	EXECUTE sys.sp_executesql 
		@sqlstmt = @sqlstringdb		
		, @params		= N'@object_name nvarchar(261), @query_id int, @plan_id int, @query_hash binary(8), @GroupBy nvarchar(60)'
		, @object_name	= @object_name
		, @query_id		= @query_id
		, @plan_id		= @plan_id
		, @query_hash	= @query_hash
		, @GroupBy		= @GroupBy;		

	SET @countDBs = @countDBs + 1;	
END;
SET @countDBs = 1; /* Reset for next loops */

/*
 SELECT * FROM #total_exec 
--*/

PRINT 'Total Executions retrieved in ' + CONVERT(varchar(30), DATEDIFF(MILLISECOND, @startDateTime, GETUTCDATE())) + ' milliseconds';
SET @startDateTime = GETUTCDATE();

/*
-- Total executions to calculate percentages 
*/
SET @sql = 'USE [?]

SELECT DB_ID()
		, SUM(rst.count_executions)									AS total_executions
		, SUM(rst.count_executions * rst.avg_duration)				AS total_duration
		, SUM(rst.count_executions * rst.avg_cpu_time)				AS total_cpu
		, SUM(rst.count_executions * rst.avg_logical_io_reads)		AS total_reads
		, SUM(rst.count_executions * rst.avg_physical_io_reads)		AS total_physical_reads
		, SUM(rst.count_executions * rst.avg_logical_io_writes)		AS total_writes
		, SUM(rst.count_executions * rst.avg_query_max_used_memory) AS total_memory
		, MAX(total_query_wait_time_ms)								AS total_query_wait_time_ms
	FROM sys.query_store_runtime_stats AS rst
	INNER JOIN #intervals AS rsti
		ON rsti.runtime_stats_interval_id = rst.runtime_stats_interval_id
			AND rsti.database_id = DB_ID()
	CROSS APPLY (SELECT SUM(total_query_wait_time_ms) AS total_query_wait_time_ms FROM #waits) AS w;
';

WHILE @countDBs <= @numDBs BEGIN 
	SELECT @dbname = dbname FROM @databases WHERE ID = @countDBs;
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

	/* SELECT @sqlstringdb */

	INSERT INTO #totals([database_id], [total_executions], [total_duration], [total_cpu], [total_reads], [total_physical_reads], [total_writes], [total_memory], [total_query_wait_time_ms])
	EXECUTE sys.sp_executesql 
		@sqlstmt = @sqlstringdb;

	SET @countDBs = @countDBs + 1;
END;
SET @countDBs = 1; /* Reset for next loops */

PRINT 'Totals retrieved in ' + CONVERT(varchar(30), DATEDIFF(MILLISECOND, @startDateTime, GETUTCDATE())) + ' milliseconds';
SET @startDateTime = GETUTCDATE();

/*
SELECT * FROM #intervals
SELECT * FROM #waits
SELECT * FROM #total_exec
SELECT * FROM #totals
--*/

/*
-- Get the final output for the period defined per database
*/
SET @sql = 'USE [?]

DROP TABLE IF EXISTS #db_intervals;
DROP TABLE IF EXISTS #db_waits;
DROP TABLE IF EXISTS #db_totals;
DROP TABLE IF EXISTS #db_total_exec;
DROP TABLE IF EXISTS #t;

CREATE TABLE #db_intervals(
	[database_id]					int NULL
	, [runtime_stats_interval_id]	bigint	NULL
	, [start_time]					datetimeoffset NULL
	, [end_time]					datetimeoffset NULL);

CREATE TABLE #db_waits(
	[database_id]							int NULL
	, [GroupBy]								binary(8) NULL
	, [runtime_stats_interval_id]			bigint	NULL
	, [avg_query_wait_time_ms]				float	NULL
	, [total_query_wait_time_ms]			bigint	NULL
	, [total_query_wait_time_ms_breakdown]	nvarchar(4000) NULL);

CREATE TABLE #db_total_exec(
	[database_id]					smallint		NULL
	, [GroupBy]						binary(8)		NULL
	, [start_time]					datetime2(0)	NULL
	, [end_time]					datetime2(0)	NULL
	, [runtime_stats_interval_id]	bigint			NULL
	, [plan_id]						bigint			NULL
	, [query_id]					bigint			NULL
	, [query_hash]					binary(8)		NULL
	, [total_executions]			bigint			NULL
	, [total_exec_successful]		bigint			NULL
	, [total_exec_aborted]			bigint			NULL
	, [total_exec_exceptions]		bigint			NULL
	, [avg_duration]				float(8)		NULL
	, [avg_cpu_time]				float(8)		NULL
	, [avg_logical_io_reads]		float(8)		NULL
	, [avg_physical_io_reads]		float(8)		NULL
	, [avg_logical_io_writes]		float(8)		NULL
	, [avg_query_max_used_memory]	float(8)		NULL
	, [avg_rowcount]				float(8)		NULL
);

CREATE TABLE #db_totals(
	[database_id]				int NULL
	, [total_executions]		bigint NULL
	, [total_duration]			float NULL
	, [total_cpu]				float NULL
	, [total_reads]				float NULL
	, [total_physical_reads]	float NULL
	, [total_writes]			float NULL
	, [total_memory]			float NULL
	, [total_query_wait_time_ms]float NULL
);

DELETE #intervals
OUTPUT deleted.* INTO #db_intervals
WHERE database_id = DB_ID();

DELETE #waits
OUTPUT deleted.* INTO #db_waits
WHERE database_id = DB_ID();

DELETE #total_exec
OUTPUT deleted.* INTO #db_total_exec
WHERE database_id = DB_ID();

DELETE #totals
OUTPUT deleted.* INTO #db_totals
WHERE database_id = DB_ID();

/* Get some data before for performance */
DECLARE @object_id int = OBJECT_ID(@object_name)

/* object name is not correct */
IF @object_id IS NULL AND @object_name IS NOT NULL BEGIN
	RAISERROR (''@object_name does not exist, please double check and run again'', 16, 1, 1) WITH NOWAIT;
	RETURN;
END;

SELECT TOP (@topNrows) 
		DB_NAME() AS database_name
		, rst.start_time
		, rst.end_time
		, q.query_id
		, qp.plan_id
		, q.query_hash
		, ISNULL(OBJECT_SCHEMA_NAME(q.object_id) + ''.'' + OBJECT_NAME(q.object_id), ''-'') AS object_name
		, rst.total_executions 
		, rst.total_exec_successful
		, rst.total_exec_aborted
		, rst.total_exec_exceptions

	/* totals */
		, (ISNULL(rst.avg_duration				, 0) * rst.total_executions) / 1000 AS total_duration_ms
		, (ISNULL(rst.avg_cpu_time				, 0) * rst.total_executions) / 1000 AS total_cpu_time_ms
		, (ISNULL(rst.avg_logical_io_reads		, 0) * rst.total_executions)		AS total_logical_io_reads
		, (ISNULL(rst.avg_physical_io_reads		, 0) * rst.total_executions)		AS total_physical_io_reads
		, (ISNULL(rst.avg_logical_io_writes		, 0) * rst.total_executions)		AS total_logical_io_writes
		, (ISNULL(rst.avg_query_max_used_memory	, 0) * rst.total_executions)		AS total_query_max_used_memory
		, (ISNULL(rst.avg_rowcount				, 0) * rst.total_executions)		AS total_rowcount
		, (ISNULL(w.total_query_wait_time_ms						, 0))			AS total_query_wait_time_ms			 
		, (ISNULL(w.total_query_wait_time_ms_breakdown			, ''-''))			AS total_query_wait_time_ms_breakdown

	/* averages */
		, ISNULL(CONVERT(bigint, rst.avg_duration / 1000		), 0) AS avg_duration_ms
		, ISNULL(CONVERT(bigint, rst.avg_cpu_time / 1000		), 0) AS avg_cpu_time_ms
		, ISNULL(CONVERT(bigint, rst.avg_logical_io_reads		), 0) AS avg_logical_io_reads
		, ISNULL(CONVERT(bigint, rst.avg_physical_io_reads		), 0) AS avg_physical_io_reads
		, ISNULL(CONVERT(bigint, rst.avg_logical_io_writes		), 0) AS avg_logical_io_writes
		, ISNULL(CONVERT(bigint, rst.avg_query_max_used_memory	), 0) AS avg_query_max_used_memory
		, ISNULL(CONVERT(bigint, rst.avg_rowcount				), 0) AS avg_rowcount
		, ISNULL(CONVERT(bigint, w.avg_query_wait_time_ms		), 0) AS avg_query_wait_time_ms

	/* percentages */
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_duration / 1000)		, 0) * rst.total_executions)	* 100 / NULLIF(t.total_duration, 0)		), 0)	AS percentge_duration
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_cpu_time / 1000)		, 0) * rst.total_executions)	* 100 / NULLIF(t.total_cpu, 0)			), 0)	AS percentge_cpu
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_logical_io_reads)	, 0) * rst.total_executions)	* 100 / NULLIF(t.total_reads, 0)		), 0)	AS percentge_reads
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_physical_io_reads)	, 0) * rst.total_executions)	* 100 / NULLIF(t.total_physical_reads, 0)), 0)	AS percentge_physical_reads
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_logical_io_writes)	, 0) * rst.total_executions)	* 100 / NULLIF(t.total_writes, 0)		), 0)	AS percentge_writes
		, ISNULL(CONVERT(decimal(5,2), (ISNULL(CONVERT(bigint, rst.avg_query_max_used_memory), 0) * rst.total_executions)	* 100 / NULLIF(t.total_memory, 0)		), 0)	AS percentge_memory
		, ISNULL(CONVERT(decimal(5,2), (w.total_query_wait_time_ms)															* 100./ NULLIF(t.total_query_wait_time_ms, 0)), 0) AS percentage_query_wait_time_ms

	/* Query Text and Plan */
		, qt.query_sql_text
		, qp.query_plan

	FROM #db_total_exec AS rst			
		INNER JOIN sys.query_store_plan AS qp
			ON qp.plan_id = rst.plan_id
		INNER JOIN sys.query_store_query AS q
			ON q.query_id = rst.query_id
		INNER JOIN sys.query_store_query_text AS qt
			ON qt.query_text_id = q.query_text_id
		LEFT JOIN #db_waits AS w
			ON w.GroupBy = rst.GroupBy
				AND w.database_id = rst.database_id
				AND ISNULL(w.runtime_stats_interval_id, -1) = ISNULL(rst.runtime_stats_interval_id, -1)
		INNER JOIN #db_totals AS t
			ON t.database_id = rst.database_id
	WHERE 1=1 
		[WHERECLAUSE]	
	ORDER BY [ORDERCLAUSE]	
';

WHILE @countDBs <= @numDBs BEGIN 
	SELECT @dbname = dbname FROM @databases WHERE ID = @countDBs;

	SET @whereclause = '';
	SET @orderclause = '';
	
	SET @sqlstringdb = REPLACE(@sql, '?', @dbname);

	/* [WHERECLAUSE]*/
	IF @query_id IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND qp.query_id = @query_id';
	END;
	IF @plan_id IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND rst.plan_id = @plan_id';
	END;
	IF @object_name IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND q.object_id = OBJECT_ID(@object_name)';
	END;
	IF @query_hash IS NOT NULL 
	BEGIN
		SET @whereclause += CHAR(10) + 'AND q.query_hash = @query_hash';
	END;

	SET @sqlstringdb = REPLACE(@sqlstringdb, '[WHERECLAUSE]', @whereclause);

	/* [ORDERCLAUSE] */
	SET @orderclause += CASE WHEN COALESCE(@object_name, CONVERT(nvarchar(261), @query_id), CONVERT(nvarchar(261), @query_hash), CONVERT(nvarchar(261), @plan_id)) IS NULL 
							THEN '' 
							ELSE 'start_time' 
						END;
	SET @orderclause += CASE @OrderBy
							WHEN 'total_executions'		THEN ', (rst.total_executions) DESC'
							WHEN 'avg_duration'			THEN ', (rst.avg_duration) DESC'
							WHEN 'avg_cpu_time'			THEN ', (rst.avg_cpu_time) DESC'
							WHEN 'avg_reads'			THEN ', (rst.avg_logical_io_reads) DESC'
							WHEN 'avg_physical_reads'	THEN ', (rst.avg_physical_io_reads) DESC'
							WHEN 'avg_writes'			THEN ', (rst.avg_logical_io_writes) DESC'
							WHEN 'avg_memory'			THEN ', (rst.avg_query_max_used_memory) DESC'
							WHEN 'total_duration'		THEN ', (rst.total_executions * rst.avg_duration) DESC'
							WHEN 'total_cpu'			THEN ', (rst.total_executions * rst.avg_cpu_time) DESC'
							WHEN 'total_reads'			THEN ', (rst.total_executions * rst.avg_logical_io_reads) DESC'
							WHEN 'total_physical_reads'	THEN ', (rst.total_executions * rst.avg_physical_io_reads) DESC'
							WHEN 'total_writes'			THEN ', (rst.total_executions * rst.avg_logical_io_writes) DESC'
							WHEN 'total_memory'			THEN ', (rst.total_executions * rst.avg_query_max_used_memory) DESC'
							ELSE ''
						END;
	SET @orderclause = CASE WHEN LEFT(@orderclause, 1) <> ',' THEN @orderclause
							ELSE RIGHT(@orderclause, LEN(@orderclause) - 1)
						END;

	SET @sqlstringdb = REPLACE(@sqlstringdb, '[ORDERCLAUSE]', @orderclause);	

	/* SELECT @sqlstringdb; */

	INSERT INTO #output ([database_name], [start_time], [end_time], [query_id], [plan_id], [query_hash], [object_name], [total_executions], [total_exec_successful], [total_exec_aborted]
						, [total_exec_exceptions], [total_duration_ms], [total_cpu_time_ms], [total_logical_io_reads], [total_physical_io_reads], [total_writes], [total_memory]
						, [total_rowcount], [total_query_wait_time_ms], [total_query_wait_time_ms_breakdown], [avg_duration_ms], [avg_cpu_time_ms], [avg_logical_io_reads]
						, [avg_physical_io_reads], [avg_logical_io_writes], [avg_query_max_used_memory], [avg_rowcount], [avg_query_wait_time_ms], [percentge_duration], [percentge_cpu]
						, [percentge_reads], [percentge_physical_reads], [percentge_writes], [percentge_memory], [percentage_query_wait_time_ms], [query_sql_text], [query_plan])
	EXECUTE sys.sp_executesql 
		@sqlstmt		= @sqlstringdb
		, @params		= N'@topNrows int, @OrderBy sysname, @object_name nvarchar(261), @query_id int, @plan_id int, @query_hash binary(8), @GroupBy nvarchar(60)'
		, @topNrows		= @topNrows 
		, @OrderBy		= @OrderBy
		, @object_name	= @object_name
		, @query_id		= @query_id
		, @plan_id		= @plan_id
		, @query_hash	= @query_hash
		, @GroupBy		= @GroupBy;
		
	SET @countDBs = @countDBs + 1;
END;

PRINT 'Final data retrieved in ' + CONVERT(varchar(30), DATEDIFF(MILLISECOND, @startDateTime, GETUTCDATE())) + ' milliseconds';
SET @startDateTime = GETUTCDATE();

SELECT [database_name]
		, CONVERT(smalldatetime, [start_time]) AS [start_time]
		, CONVERT(smalldatetime, [end_time]) AS [end_time]
		, ISNULL(TRY_CONVERT(varchar(30), [query_id]), '-') AS [query_id]
		, ISNULL(TRY_CONVERT(varchar(30), [plan_id]), '-') AS [plan_id]
		, ISNULL('0x' + (TRY_CONVERT(varchar(30), [query_hash], 2)), '-') AS [query_hash]
		, [object_name]
		, [total_executions]
		, [total_exec_successful]
		, [total_exec_aborted]
		, [total_exec_exceptions]
		, '(Successful:' + CONVERT(varchar(100), [total_exec_successful]) + 
			', Aborted:' + CONVERT(varchar(100), [total_exec_aborted]) + 
			', Exceptions:' + CONVERT(varchar(100), [total_exec_exceptions]) + ')' AS [total_executions_breakdown]
		, [total_duration_ms]
		, ISNULL(NULLIF (CONVERT(VARCHAR(24), ([total_duration_ms]/1000) / 3600 / 24 ),'0') + '.', '') + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_duration_ms]/1000) / 3600 % 24 ), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_duration_ms]/1000) / 60 % 60), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_duration_ms]/1000) % 60), 2) AS [total_duration_hhmmss]
		
		, [total_cpu_time_ms]
		, ISNULL(NULLIF (CONVERT(VARCHAR(24), ([total_cpu_time_ms]/1000) / 3600 / 24 ),'0') + '.', '') + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_cpu_time_ms]/1000) / 3600 % 24 ), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_cpu_time_ms]/1000) / 60 % 60), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), ([total_cpu_time_ms]/1000) % 60), 2) AS [total_cpu_hhmmss]

		, [avg_duration_ms]
		, [avg_cpu_time_ms]
		, [avg_logical_io_reads]
		, CONVERT(decimal(15,2), [avg_logical_io_reads]		/ 128.) AS [avg_logical_mb_read]
		, [avg_physical_io_reads]
		, CONVERT(decimal(15,2), [avg_physical_io_reads]	/ 128.) AS [avg_physical_mb_read]
		, [avg_logical_io_writes]
		, CONVERT(decimal(15,2), [avg_logical_io_writes]	/ 128.) AS [avg_mb_written]
		, [avg_query_max_used_memory]
		, CONVERT(decimal(15,2), [avg_query_max_used_memory]/ 128.) AS [avg_mb_memory]
		, [avg_rowcount]
		, [avg_query_wait_time_ms]
		, [total_logical_io_reads]
		, CONVERT(decimal(15,2), [total_logical_io_reads]	/ 128.				) AS [total_logical_mb_read]
		, CONVERT(decimal(15,2), [total_logical_io_reads]	/ 128. / 1024		) AS [total_logical_gb_read]
		, CONVERT(decimal(15,2), [total_logical_io_reads]	/ 128. / 1024 / 1024) AS [total_logical_tb_read]
		, [total_physical_io_reads]
		, CONVERT(decimal(15,2), [total_physical_io_reads]	/ 128.)					AS [total_physical_mb_read]
		, CONVERT(decimal(15,2), [total_physical_io_reads]	/ 128. / 1024)			AS [total_physical_gb_read]
		, CONVERT(decimal(15,2), [total_physical_io_reads]	/ 128. / 1024 / 1024)	AS [total_physical_tb_read]
		, [total_writes]
		, [total_memory]
		, CONVERT(decimal(15,2), [total_memory]	/ 128.) AS [total_mb_memory]
		, [total_rowcount]
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
		/*, '"' + LEFT(REPLACE(query_sql_text, '"', '&quote;'), 49990) + '"' AS query_sql_text */ /* use this to copy paste into a spreadsheet */
		, ISNULL(TRY_CONVERT(xml, query_plan), query_plan) AS query_plan
		/*, query_plan --*/ /* use this if the XML doesn't parse for some reason */
FROM #output
ORDER BY Id;

OnError:
GO