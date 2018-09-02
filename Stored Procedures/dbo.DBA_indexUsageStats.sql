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
-- Date:		May 2013
-- Description:	Find all indexes which are not in use (only user tables)
--				and generate scripts to DROP and CREATE them back (just in case they were required)
--
--				The script will run for all USER DATABASES or a given USER DATABASE
--
--				The script returns 1 or 2 resultsets
--					- 1 List of index wich are not used since last reboot
--						- Drop Index statements
--						- Create Index statements in case you need the indexes back
--						- Database Name
--						- Table Name
--						- Index Name
--						- Is Primary Key index
--						- Row count 
--						- Size in MB
--						- User seeks (since last start)
--						- User scans (since last start)
--						- User lookups (since last start)
--						- User updates (since last start)
--					- 2 Total Size of unused index and per database
--						- Database Name
--						- Unused space in GB
--						- Total Number of indexes
--
-- Change Log:	- RAG 19/09/2013 - Changed global temporary table for a local to avoid concurrency problems
--				- RAG 19/09/2013 - Included clause [is_ms_shipped <> 1] to avoid tables automatically created by replication processes
--				- RAG 19/09/2013 - Calculate Totals based on the first resultset
--				- RAG 31/10/2013 - Add filter to not process objects created by an internal SQL Server component
--				- RAG 13/12/2013 - Added parameters 
--									@tableName -- will display only indexes for the given table if specified
--									@OnlyUnused -- Will display all indexes when 0
--				- RAG 1003/2014 - Added variable @lowUsageThreshold to control the threshold to list an index
-- =============================================
CREATE PROCEDURE [dbo].[DBA_indexUsageStats]
	@dbname					SYSNAME		= NULL
	, @tableName			SYSNAME		= NULL
	, @includePrimaryKey	BIT			= 0		-- 1 Will include PK indexes
	, @sortInTempdb			NVARCHAR(3)	= 'ON'	-- set to on to reduce creation time, watch tempdb though!!!
	, @dropExisting			NVARCHAR(3) = 'OFF'	-- Default OFF
	, @online				NVARCHAR(3)	= 'ON'	-- Set to ON to avoid table locks
	, @onlyUnused			BIT			= 1		-- 
	, @includeTotals		BIT			= 1		-- Will return the second recordset
AS 
BEGIN
	
	SET NOCOUNT ON
	
	-- Set default values for parameters if are NULL
	SET @includePrimaryKey	= ISNULL(@includePrimaryKey, 0)
	SET @sortInTempdb		= ISNULL(@sortInTempdb, 'ON')
	SET @dropExisting		= ISNULL(@dropExisting, 'OFF')
	SET @online				= ISNULL(@online, 'ON')
	SET @onlyUnused			= ISNULL(@onlyUnused, 1)
	SET @includeTotals		= ISNULL(@includeTotals, 1)

	CREATE TABLE #result (
		ID							INT IDENTITY(1,1)
		, DROP_INDEX_STATEMENT		NVARCHAR(4000)
		, CREATE_INDEX_STATEMENT	NVARCHAR(4000)
		, index_columns				NVARCHAR(4000)
		, included_columns			NVARCHAR(4000)
		, filter					NVARCHAR(4000)
		, dbname					SYSNAME NULL
		, tableName					SYSNAME NULL
		, indexName					SYSNAME NULL
		, indexType					SYSNAME NULL
		, is_primary_key			VARCHAR(3) NULL
		, row_count					BIGINT NULL
		, size_MB					BIGINT NULL
		, user_seeks				BIGINT NULL
		, user_scans				BIGINT NULL
		, user_lookups				BIGINT NULL
		, user_updates				BIGINT NULL
	)

	DECLARE @databases	TABLE (ID			INT IDENTITY(1,1)
								, dbname	SYSNAME
								, files		INT)

	DECLARE @numDB			INT
			, @countDB		INT = 1
			, @sqlString	NVARCHAR(MAX)

	INSERT @databases (dbname)
		SELECT TOP 1000 name 
			FROM sys.databases d 
			WHERE 1=1
				AND d.name LIKE ISNULL(@dbname, name)
				AND d.database_id > 4
				AND d.name NOT LIKE 'ReportServer%'
				AND state = 0 -- Online
			ORDER BY name

	SET @numDB = @@ROWCOUNT;

	WHILE @countDB <= @numDB BEGIN
		SET @dbname = (SELECT dbname from @databases WHERE ID = @countDB)

		-- Dummy Line to get statements commented out
		INSERT INTO #result (DROP_INDEX_STATEMENT, CREATE_INDEX_STATEMENT, dbname)
			SELECT  char(10) + '/*' + char(10) + N'USE ' + QUOTENAME(@dbname) + char(10) + 'GO'
					, char(10) + '/*' + char(10) + N'USE ' + QUOTENAME(@dbname) + char(10) + 'GO'
					, QUOTENAME(@dbname)

		SET @sqlString = N'
		
			USE ' + QUOTENAME(@dbname) + N'	

			DECLARE @tableName	SYSNAME = ' + CASE WHEN @tableName IS NULL THEN N'NULL' ELSE N'''' + @tableName + N'''' END + N'
			DECLARE @onlyUnused BIT		= ' + CONVERT(NVARCHAR(1), ISNULL(@onlyUnused, 1)) + CONVERT(NVARCHAR(MAX), N'
			DECLARE @lowUsageThreshold INT = 100
			
			PRINT @tableName

			-- Get indexes not in use since last boot up
			SELECT  			
					N''DROP INDEX '' + QUOTENAME(ix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + char(10) + N''GO'' AS DROP_INDEX_STATEMENT
					,
					N''CREATE '' + 
									CASE WHEN INDEXPROPERTY(ix.object_id, ix.name, ''IsUnique'') = 1 THEN N''UNIQUE '' ELSE N'''' END + 
									CASE WHEN INDEXPROPERTY(ix.object_id, ix.name, ''IsClustered'') = 1 THEN N''CLUSTERED'' ELSE N''NONCLUSTERED'' END + 
					N'' INDEX '' + QUOTENAME(ix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + char(10) +
						N''('' + char(10) +
						(SELECT STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name) + CASE WHEN ixc.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END + char(10)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = ix.object_id 
												AND ixc.index_id = ix.index_id 
												AND ixc.is_included_column = 0
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''')) + 
						N'')'' + char(10) +
						ISNULL((SELECT N''INCLUDE ('' + STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = ix.object_id 
												AND ixc.index_id = ix.index_id 
												AND ixc.is_included_column = 1
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''') + 
						N'')'') + char(10) , '''') +
						ISNULL( (CASE WHEN ix.has_filter = 1 THEN ''WHERE '' + ix.filter_definition + char(10) ELSE NULL END), '''' ) +
						N''WITH (PAD_INDEX = '' + CASE WHEN ix.is_padded = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', STATISTICS_NORECOMPUTE = '' + CASE WHEN DATABASEPROPERTYEX(DB_ID(), ''IsAutoUpdateStatistics'') = 1 THEN N''ON'' ELSE ''OFF'' END +
						N'', SORT_IN_TEMPDB = '' + @sortInTempdb + 
						N'', IGNORE_DUP_KEY = '' + CASE WHEN ix.ignore_dup_key = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', DROP_EXISTING = '' + @dropExisting + 
						N'', ONLINE = '' + @online + 
						N'', ALLOW_ROW_LOCKS = '' + CASE WHEN ix.allow_row_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', ALLOW_PAGE_LOCKS = '' + CASE WHEN ix.allow_page_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						CASE WHEN ix.fill_factor = 0 THEN N'''' ELSE 
						N'', FILLFACTOR = '' + CONVERT(NVARCHAR(3),fill_factor) END +
					N'') ON '' + QUOTENAME(d.name) + char(10) + N''GO'' + char(10) AS CREATE_INDEX_STATEMENT			
					
					
					
					, STUFF( (SELECT N'', '' + QUOTENAME(c.name) + CASE WHEN ixc.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END +
									CASE WHEN c.is_nullable = 1 THEN '' (NULL)'' ELSE '''' END
								FROM sys.index_columns as ixc 
									INNER JOIN sys.columns as c
										ON ixc.object_id = c.object_id
											AND ixc.column_id = c.column_id
								WHERE ixc.object_id = ix.object_id 
									AND ixc.index_id = ix.index_id 
									AND ixc.is_included_column = 0
								ORDER BY ixc.index_column_id
								FOR XML PATH ('''')), 1,2,'''')
					
					, STUFF( (SELECT N'', '' + QUOTENAME(c.name)
									FROM sys.index_columns as ixc 
										INNER JOIN sys.columns as c
											ON ixc.object_id = c.object_id
												AND ixc.column_id = c.column_id
									WHERE ixc.object_id = ix.object_id 
										AND ixc.index_id = ix.index_id 
										AND ixc.is_included_column = 1
									ORDER BY ixc.index_column_id
									FOR XML PATH ('''')), 1,2,'''')
					, ix.filter_definition

					, QUOTENAME(DB_NAME(DB_ID()))
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) AS TableName
					, ix.name
					, ix.type_desc
					, CASE WHEN ix.is_primary_key = 1 THEN ''Yes'' WHEN ix.is_primary_key = 0 THEN  ''No'' END
					, p.row_count
					, (p.reserved_page_count*8)/1024 AS [size (MB)]
					, ius.user_seeks
					, ius.user_scans
					, ius.user_lookups
					, ius.user_updates
				FROM sys.indexes AS ix
					INNER JOIN sys.objects AS o 
						ON o.object_id = ix.object_id
					INNER JOIN sys.data_spaces AS d
						ON d.data_space_id = ix.data_space_id
					LEFT JOIN sys.dm_db_index_usage_stats AS ius
						ON ix.object_id = ius.object_id 
							AND ix.index_id = ius.index_id
							AND ( ISNULL(ius.database_id, DB_ID()) = DB_ID() )
					LEFT JOIN sys.dm_db_partition_stats AS p 
						ON p.object_id = ix.object_id 
							AND p.index_id = ix.index_id
				WHERE o.type = ''U''
					AND o.is_ms_shipped = 0
					AND ix.type > 0
					AND ( @includePrimaryKey = 1 OR ( @includePrimaryKey = 0 AND ix.is_primary_key = 0 ) )
					AND ( ( @onlyUnused = 1 AND ISNULL( ius.user_seeks, 0 ) <= @lowUsageThreshold ) OR @onlyUnused = 0 )
					--AND ( ISNULL( ius.user_scans, 0 ) = 0 )
					AND ( @tableName COLLATE DATABASE_DEFAULT IS NULL OR ix.object_id = OBJECT_ID(@tableName)  )
				ORDER BY o.name, ix.is_primary_key DESC, ix.name

		')
		INSERT INTO #result
			EXEC sp_executesql @sqlString
					, N'@includePrimaryKey BIT, @sortInTempdb NVARCHAR(3), @dropExisting NVARCHAR(3), @online NVARCHAR(3)'
					, @includePrimaryKey	= @includePrimaryKey
					, @sortInTempdb			= @sortInTempdb
					, @dropExisting			= @dropExisting
					, @online				= @online

		-- Dummy Line to end commented statement 
		INSERT INTO #result (DROP_INDEX_STATEMENT, CREATE_INDEX_STATEMENT, dbname)
			SELECT  '*/', '*/', QUOTENAME(@dbname)

		SET @countDB = @countDB + 1
	END

	-- Time to retrieve all data collected
	SELECT 	dbname
			, tableName
			, indexName
			, indexType
			, is_primary_key
			, row_count	
			, size_MB
			, user_seeks
			, user_scans
			, user_lookups
			, user_updates
			, index_columns
			, included_columns
			, filter
			, DROP_INDEX_STATEMENT
			, CREATE_INDEX_STATEMENT			
		FROM #result
		ORDER BY ID ASC

	IF @includeTotals = 1 BEGIN
		SELECT	dbname
				, CONVERT( DECIMAL(10,2), SUM(ISNULL(size_MB,0) / 1024.) ) AS IndexSize_GB
				, COUNT(indexName) AS total
			FROM #result
			GROUP BY GROUPING SETS ((dbname), ())
			HAVING COUNT(indexName) > 0
	END

	DROP TABLE #result			
END




GO
