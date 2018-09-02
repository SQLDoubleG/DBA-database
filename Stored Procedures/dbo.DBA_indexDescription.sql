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
-- Create date: 17/07/2013
-- Description:	Returns descriptive index information for a database, schema or table specified.
--
-- Assupmtions:	
--
-- Change Log:	14/11/2013 RAG Created
--				08/07/2014 RAG Added support for indexed views
--				04/11/2014 RAG Added column fill_factor
--				14/05/2018 RAG Added column partition_number 
--				
-- =============================================
CREATE PROCEDURE [dbo].[DBA_indexDescription] 
	@dbname					SYSNAME		= NULL
	, @schemaName			SYSNAME		= NULL
	, @tableName			SYSNAME		= NULL
	, @sortInTempdb			NVARCHAR(3)	= 'ON'	-- set to on to reduce creation time, watch tempdb though!!!
	, @dropExisting			NVARCHAR(3) = 'OFF'	-- Default OFF
	, @online				NVARCHAR(3)	= 'ON'	-- Set to ON to avoid table locks
	, @maxdop				TINYINT		= 0		-- 0 to use the actual number of processors or fewer based on the current system workload
	, @sortOrder			SYSNAME		= 'index_id'
	, @includeTotals		BIT			= 1		-- Will return the second recordset
AS
BEGIN
	
	SET NOCOUNT ON

	SET @sortInTempdb	= ISNULL(@sortInTempdb, 'ON')
	SET @dropExisting	= ISNULL(@dropExisting, 'OFF')
	SET @online			= ISNULL(@online, 'ON')
	SET @maxdop			= ISNULL(@maxdop, 0)
	SET @sortOrder		= ISNULL(@sortOrder, 'index_id')

	
	CREATE TABLE #result 
		( ID						INT IDENTITY(1,1)	NOT NULL
		, DROP_INDEX_STATEMENT		NVARCHAR(4000)		NULL
		, CREATE_INDEX_STATEMENT	NVARCHAR(4000)		NULL
		, [index_columns]			NVARCHAR(4000)		NULL
		, included_columns			NVARCHAR(4000)		NULL
		, filter					NVARCHAR(4000)		NULL
		, dbname					SYSNAME				NULL
		, tableName					SYSNAME				NULL
		, index_id					INT					NULL
		, partition_number			INT					NULL
		, index_name				SYSNAME				NULL
		, index_type				SYSNAME				NULL
		, is_primary_key			VARCHAR(3)			NULL
		, is_unique					VARCHAR(3)			NULL
		, is_disabled				VARCHAR(3)			NULL
		, row_count					INT NULL
		, reserved_MB				DECIMAL(10,2)		NULL
		, size_MB					DECIMAL(10,2)		NULL
		, fill_factor				TINYINT				NULL
		, user_seeks				BIGINT				NULL
		, user_scans				BIGINT				NULL
		, user_lookups				BIGINT				NULL
		, user_updates				BIGINT				NULL
		, filegroup_desc			SYSNAME				NULL
		, data_compression_desc		SYSNAME				NULL		
	)

	CREATE TABLE #databases 
		( ID			INT IDENTITY
		, dbname		SYSNAME)
		
	DECLARE @sqlCmd		VARCHAR(8000)
	DECLARE @sqlString	NVARCHAR(MAX)
			, @countDB	INT = 1
			, @numDB	INT

	INSERT INTO #databases 
		SELECT TOP 100 PERCENT name 
			FROM sys.databases 
			WHERE [name] NOT IN ('model', 'tempdb') 
				AND state = 0 
				AND name LIKE ISNULL(@dbname, name)
			ORDER BY name ASC		

	SET @numDB = @@ROWCOUNT

	WHILE @countDB <= @numDB BEGIN
		SET @dbname = (SELECT dbname from #databases WHERE ID = @countDB)

		-- Dummy Line to get statements commented out
		--INSERT INTO #result (DROP_INDEX_STATEMENT, CREATE_INDEX_STATEMENT, dbname)
		--	SELECT  char(10) + '/*' + char(10) + N'USE ' + QUOTENAME(@dbname) + char(10) + 'GO'
		--			, char(10) + '/*' + char(10) + N'USE ' + QUOTENAME(@dbname) + char(10) + 'GO'
		--			, QUOTENAME(@dbname)

		SET @sqlString = N'
		
			USE ' + QUOTENAME(@dbname) + N'	
			
			DECLARE @tableName SYSNAME = ' + CASE WHEN @tableName IS NULL THEN N'NULL' ELSE N'''' + @tableName + N'''' END +  N'
			DECLARE @schemaName SYSNAME = ' + CASE WHEN @schemaName IS NULL THEN N'NULL' ELSE N'''' + @schemaName + N'''' END +  CONVERT( NVARCHAR(MAX), N'

			-- Get indexes 
			SELECT  			
					N''DROP INDEX '' + QUOTENAME(ix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) + N''GO'' AS DROP_INDEX_STATEMENT
					,
					N''CREATE '' + 
						CASE 
							-- CLUSTERED, NON CLUSTERED
							WHEN ix.type IN (1, 2) THEN
								CASE WHEN ix.is_unique = 1 THEN N''UNIQUE '' ELSE N'''' END +
								CASE WHEN INDEXPROPERTY(ix.object_id, ix.name, ''IsClustered'') = 1 THEN N''CLUSTERED'' ELSE N''NONCLUSTERED'' END
						END +
						N'' INDEX '' + QUOTENAME(ix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) +
						N''('' + CHAR(10) +
						(SELECT STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name) + CASE WHEN ix.type IN (1, 2) THEN CASE WHEN ixc.is_descending_key = 1 THEN N'' DESC'' ELSE N'' ASC'' END ELSE N'''' END + CHAR(10)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = ix.object_id 
												AND ixc.index_id = ix.index_id 
												AND ixc.is_included_column = 0
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''')) + 
						N'')'' + CHAR(10) +
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
						N'')'') + CHAR(10) , '''') +
						ISNULL( (CASE WHEN ix.has_filter = 1 THEN ''WHERE '' + ix.filter_definition + CHAR(10) ELSE NULL END), '''' ) +

						N''WITH ('' + 
							CHAR(10) +
							N''PAD_INDEX = '' + CASE WHEN ix.is_padded = 1 THEN N''ON'' ELSE N''OFF'' END +
							CASE WHEN ix.fill_factor = 0 THEN N'''' ELSE N'', FILLFACTOR = '' + CONVERT(NVARCHAR(3),ix.fill_factor) END + 
							N'', SORT_IN_TEMPDB = '' + @sortInTempdb + 
							CASE WHEN ix.type IN (1, 2) THEN N'', IGNORE_DUP_KEY = '' + CASE WHEN ix.ignore_dup_key = 1 THEN N''ON'' ELSE N''OFF'' END ELSE N'''' END +
							N'', STATISTICS_NORECOMPUTE = '' + CASE WHEN DATABASEPROPERTYEX(DB_ID(), ''IsAutoUpdateStatistics'') = 1 THEN N''ON'' ELSE ''OFF'' END +
							N'', DROP_EXISTING = '' + @dropExisting + 
							CASE WHEN ix.type IN (1, 2) AND SERVERPROPERTY(''EngineEdition'') = 3 THEN N'', ONLINE = '' + @online ELSE N'''' END + 						
							N'', ALLOW_ROW_LOCKS = '' + CASE WHEN ix.allow_row_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
							N'', ALLOW_PAGE_LOCKS = '' + CASE WHEN ix.allow_page_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
							CASE WHEN @maxdop <> 0 THEN N'', MAXDOP = '' + CONVERT(NVARCHAR,@maxdop) ELSE N'''' END + 
							CASE WHEN p.data_compression <> 0 THEN N'', DATA_COMPRESSION = '' + p.data_compression_desc COLLATE DATABASE_DEFAULT ELSE '''' END + 
							CHAR(10) +
						N'')'' + 
						
						CASE WHEN ix.type IN (1, 2) 
							THEN '' ON '' + QUOTENAME(d.name) 
							ELSE N'''' 
						END + CHAR(10) + N''GO'' + CHAR(10) AS CREATE_INDEX_STATEMENT			

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
					, QUOTENAME(DB_NAME()) AS DatabaseName
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) AS TableName
					, ix.index_id AS index_id 
					, p.partition_number
					, ix.name
					, ix.type_desc
					, CASE WHEN ix.is_primary_key = 1	THEN ''Yes'' WHEN ix.is_primary_key = 0 THEN  ''No'' END AS is_primary_key
					, CASE WHEN ix.is_unique = 1		THEN ''Yes'' WHEN ix.is_unique = 0		THEN  ''No'' END AS is_unique
					, CASE WHEN ix.is_disabled = 1		THEN ''Yes'' WHEN ix.is_disabled = 0	THEN  ''No'' END AS is_disabled
					, ps.row_count
					, ( ps.reserved_page_count * 8 ) / 1024. 
					, ( ps.used_page_count * 8 ) / 1024. 
					, ix.fill_factor
					, ius.user_seeks
					, ius.user_scans
					, ius.user_lookups
					, ius.user_updates
					, d.name AS filegroup_desc
					, p.data_compression_desc
				FROM sys.indexes AS ix
					INNER JOIN sys.objects AS o 
						ON o.object_id = ix.object_id
					INNER JOIN sys.data_spaces AS d
						ON d.data_space_id = ix.data_space_id
					INNER JOIN sys.dm_db_partition_stats AS ps
						ON ps.object_id = ix.object_id 
							AND ps.index_id = ix.index_id
					INNER JOIN sys.partitions AS p 
						ON p.object_id = ix.object_id 
							AND p.index_id = ix.index_id
							AND p.partition_number = ps.partition_number
					LEFT JOIN sys.dm_db_index_usage_stats AS ius
						ON ius.object_id = ix.object_id 
							AND ius.index_id = ix.index_id
							AND ius.database_id = DB_ID()
				WHERE o.type IN (''U'', ''V'')
					AND o.is_ms_shipped <> 1
					AND ix.type > 0				
					AND o.name LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, o.name)
					AND SCHEMA_NAME(o.schema_id) LIKE ISNULL(@schemaName COLLATE DATABASE_DEFAULT, SCHEMA_NAME(o.schema_id))

					--AND ( ISNULL(@tableName COLLATE DATABASE_DEFAULT, '''') = '''' OR o.name LIKE @tableName )
					--AND ( ISNULL(@schemaName COLLATE DATABASE_DEFAULT, '''') = '''' OR SCHEMA_NAME(o.schema_id) LIKE @schemaName )
			
			UNION ALL 

			-- Get XML indexes 
			SELECT  			
					N''DROP INDEX '' + QUOTENAME(xix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) + N''GO'' AS DROP_INDEX_STATEMENT
					,
					N''CREATE '' + 
								CASE WHEN ix.type_desc = ''CLUSTERED'' THEN N''PRIMARY '' ELSE N'''' END + xix.type_desc +
						N'' INDEX '' + QUOTENAME(xix.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) +
						N''('' + CHAR(10) +
						(SELECT STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name) + CHAR(10)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = xix.object_id 
												AND ixc.index_id = xix.index_id 
												AND ixc.is_included_column = 0
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''')) + 
						N'')'' + CHAR(10) +
						ISNULL((SELECT N''INCLUDE ('' + STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = xix.object_id 
												AND ixc.index_id = xix.index_id 
												AND ixc.is_included_column = 1
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''') + 
						N'')'') + CHAR(10) , '''') +
						ISNULL( (CASE WHEN xix.has_filter = 1 THEN ''WHERE '' + xix.filter_definition + CHAR(10) ELSE NULL END), '''' ) +

						CASE 
							WHEN xix.secondary_type IS NOT NULL 
								THEN N''USING XML INDEX '' + QUOTENAME(using_xml_index.name) + '' FOR '' + xix.secondary_type_desc COLLATE DATABASE_DEFAULT + CHAR(10)
							ELSE N''''
						END + 
						N''WITH ('' + 
						N''PAD_INDEX = '' + CASE WHEN xix.is_padded = 1 THEN N''ON'' ELSE N''OFF'' END +
						CASE WHEN xix.fill_factor = 0 THEN N'''' ELSE N'', FILLFACTOR = '' + CONVERT(NVARCHAR(3),xix.fill_factor) END + 
						N'', SORT_IN_TEMPDB = '' + @sortInTempdb + 
						N'', IGNORE_DUP_KEY = '' + CASE WHEN xix.ignore_dup_key = 1 THEN N''ON'' ELSE N''OFF'' END  + 
						N'', DROP_EXISTING = '' + @dropExisting + 
						-- ONLINE option is not available for xml indexes						
						N'', ALLOW_ROW_LOCKS = '' + CASE WHEN xix.allow_row_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', ALLOW_PAGE_LOCKS = '' + CASE WHEN xix.allow_page_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						CASE WHEN p.data_compression <> 0 THEN N'', DATA_COMPRESSION = '' + p.data_compression_desc COLLATE DATABASE_DEFAULT ELSE '''' END + 
						CASE WHEN @maxdop <> 0 THEN N'', MAXDOP = '' + CONVERT(NVARCHAR,@maxdop) ELSE N'''' END + 
						N'')'' + 
						CHAR(10) + N''GO'' + CHAR(10) AS CREATE_INDEX_STATEMENT			

					, STUFF((SELECT N'', '' + QUOTENAME(c.name) + CHAR(10)
								FROM sys.index_columns as ixc 
									INNER JOIN sys.columns as c
										ON ixc.object_id = c.object_id
											AND ixc.column_id = c.column_id
								WHERE ixc.object_id = xix.object_id 
									AND ixc.index_id = xix.index_id 
									AND ixc.is_included_column = 0
								ORDER BY ixc.index_column_id
								FOR XML PATH ('''')), 1,2,'''')
					
					, STUFF((SELECT N'', '' + QUOTENAME(c.name)
								FROM sys.index_columns as ixc 
									INNER JOIN sys.columns as c
										ON ixc.object_id = c.object_id
											AND ixc.column_id = c.column_id
								WHERE ixc.object_id = xix.object_id 
									AND ixc.index_id = xix.index_id 
									AND ixc.is_included_column = 1
								ORDER BY ixc.index_column_id
								FOR XML PATH ('''')), 1,2,'''') 
					, ix.filter_definition

					, QUOTENAME(DB_NAME())
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) AS TableName
					, xix.index_id	
					, p.partition_number			
					, xix.name
					, xix.type_desc + N'' ('' + CASE WHEN xix.secondary_type_desc IS NULL THEN ''PRIMARY'' ELSE xix.secondary_type_desc END + N'')''
					, CASE WHEN xix.is_primary_key = 1	THEN ''Yes'' WHEN xix.is_primary_key = 0	THEN  ''No'' END
					, CASE WHEN xix.is_unique = 1		THEN ''Yes'' WHEN xix.is_unique = 0			THEN  ''No'' END AS is_unique
					, CASE WHEN xix.is_disabled = 1		THEN ''Yes'' WHEN xix.is_disabled = 0		THEN  ''No'' END AS is_disabled
					, p2.row_count
					, ( p2.reserved_page_count * 8 ) / 1024. 
					, ( p2.used_page_count * 8 ) / 1024. 
					, xix.fill_factor
					, ius2.user_seeks
					, ius2.user_scans
					, ius2.user_lookups
					, ius2.user_updates
					, d.name AS filegroup_desc
					, p.data_compression_desc

				FROM sys.xml_indexes AS xix
					INNER JOIN sys.objects AS o 
						ON o.object_id = xix.object_id
		
					-- Workaround to get the correct object_id, index_id to get partition_stats and usage_stats
					INNER JOIN sys.indexes AS ix
						ON ix.name = xix.name
							AND ix.object_id <> xix.object_id
					LEFT JOIN sys.dm_db_partition_stats AS p2
						ON p2.object_id = ix.object_id
							AND p2.index_id = ix.index_id

					INNER JOIN sys.partitions AS p 
						ON p.object_id = p2.object_id 
							AND p.index_id = p2.index_id
							AND p.partition_number = p2.partition_number

					LEFT JOIN sys.dm_db_index_usage_stats AS ius2
						ON ius2.object_id = ix.object_id
							AND ius2.index_id = ix.index_id
							AND ius2.database_id = DB_ID()
		
					-- Get name of the PRIMARY xml index for the SECONDARY xml index
					LEFT JOIN sys.indexes AS using_xml_index
						ON using_xml_index.object_id = xix.object_id
							AND using_xml_index.index_id = xix.using_xml_index_id

					LEFT JOIN sys.data_spaces AS d
						ON d.data_space_id = ix.data_space_id

				WHERE OBJECTPROPERTY ( xix.object_id , ''IsUserTable'' ) = 1 -- o.type = ''U''
					AND OBJECTPROPERTY ( xix.object_id , ''IsMSShipped'' ) = 0 -- o.is_ms_shipped <> 1
					AND o.name LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, o.name)
					AND SCHEMA_NAME(o.schema_id) LIKE ISNULL(@schemaName COLLATE DATABASE_DEFAULT, SCHEMA_NAME(o.schema_id))

					--AND ( ISNULL(@tableName COLLATE DATABASE_DEFAULT, '''') = '''' OR o.name LIKE @tableName )
					--AND ( ISNULL(@schemaName COLLATE DATABASE_DEFAULT, '''') = '''' OR SCHEMA_NAME(o.schema_id) LIKE @schemaName )


			UNION ALL 			
			
			-- Get SPATIAL Indexes
			SELECT  			
					N''DROP INDEX '' + QUOTENAME(six.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) + N''GO'' AS DROP_INDEX_STATEMENT
					,
					N''CREATE '' + six.type_desc +
						N'' INDEX '' + QUOTENAME(six.name) + N'' ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + CHAR(10) +
						N''('' + CHAR(10) +
						(SELECT STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name) + CHAR(10)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = six.object_id 
												AND ixc.index_id = six.index_id 
												AND ixc.is_included_column = 0
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''')) + 
						N'')'' + CHAR(10) +
						ISNULL((SELECT N''INCLUDE ('' + STUFF( 
										(SELECT N'', '' + QUOTENAME(c.name)
											FROM sys.index_columns as ixc 
												INNER JOIN sys.columns as c
													ON ixc.object_id = c.object_id
														AND ixc.column_id = c.column_id
											WHERE ixc.object_id = six.object_id 
												AND ixc.index_id = six.index_id 
												AND ixc.is_included_column = 1
											ORDER BY ixc.index_column_id
											FOR XML PATH ('''')), 1,2,'''') + 
						N'')'') + CHAR(10) , '''') +
						ISNULL( (CASE WHEN six.has_filter = 1 THEN ''WHERE '' + six.filter_definition + CHAR(10) ELSE NULL END), '''' ) +

						N''USING '' + six.tessellation_scheme + CHAR(10) + 
						N''WITH ('' + 
						
						-- <bounding_box>
							ISNULL(
								CHAR(10) +
								N''BOUNDING_BOX = ('' + 
									N''xmin = '' + CONVERT(NVARCHAR, sixt.bounding_box_xmin) + 
									N'', ymin = '' + CONVERT(NVARCHAR, sixt.bounding_box_ymin) + 
									N'', xmax = '' + CONVERT(NVARCHAR, sixt.bounding_box_xmax) + 
									N'', ymax = '' + CONVERT(NVARCHAR, sixt.bounding_box_ymax) + N''), '', '''') + 
						
						-- <tesselation_grid>		
							ISNULL(
								CHAR(10) +
								NULLIF( (
								N''GRIDS = ('' + 
									ISNULL(N''LEVEL_1 = '' + sixt.level_1_grid_desc, '''') + 
									ISNULL(N'', LEVEL_2 = '' + sixt.level_2_grid_desc, '''') + 
									ISNULL(N'', LEVEL_3 = '' + sixt.level_3_grid_desc, '''') + 
									ISNULL(N'', LEVEL_4 = '' + sixt.level_4_grid_desc, '''') + N''),''), ''GRIDS = (),''), '''') + 
							
						CHAR(10) +
						-- <tesseallation_cells_per_object>			
							N''CELLS_PER_OBJECT = '' + CONVERT(NVARCHAR(5), sixt.cells_per_object) + N'', '' +
						
						CHAR(10) +
						N''PAD_INDEX = '' + CASE WHEN six.is_padded = 1 THEN N''ON'' ELSE N''OFF'' END +
						CASE WHEN six.fill_factor = 0 THEN N'''' ELSE N'', FILLFACTOR = '' + CONVERT(NVARCHAR(3),six.fill_factor) END + 
						N'', SORT_IN_TEMPDB = '' + @sortInTempdb + 
						N'', IGNORE_DUP_KEY = '' + CASE WHEN six.ignore_dup_key = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', STATISTICS_NORECOMPUTE = '' + CASE WHEN DATABASEPROPERTYEX(DB_ID(), ''IsAutoUpdateStatistics'') = 1 THEN N''ON'' ELSE ''OFF'' END +
						N'', DROP_EXISTING = '' + @dropExisting + 
						N'', ONLINE = '' + CASE WHEN SERVERPROPERTY(''EngineEdition'') = 3 THEN @online ELSE N''OFF'' END + 
						N'', ALLOW_ROW_LOCKS = '' + CASE WHEN six.allow_row_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						N'', ALLOW_PAGE_LOCKS = '' + CASE WHEN six.allow_page_locks = 1 THEN N''ON'' ELSE N''OFF'' END +
						CASE WHEN @maxdop <> 0 THEN N'', MAXDOP = '' + CONVERT(NVARCHAR,@maxdop) ELSE N'''' END + 
						CASE WHEN p.data_compression <> 0 THEN N'', DATA_COMPRESSION = '' + p.data_compression_desc COLLATE DATABASE_DEFAULT ELSE '''' END + 
						CHAR(10) + N'')'' +
						N'' ON '' + QUOTENAME(d.name) COLLATE DATABASE_DEFAULT + CHAR(10) + N''GO'' + CHAR(10) AS CREATE_INDEX_STATEMENT			
					
					, STUFF((SELECT N'', '' + QUOTENAME(c.name) + CHAR(10)
								FROM sys.index_columns as ixc 
									INNER JOIN sys.columns as c
										ON ixc.object_id = c.object_id
											AND ixc.column_id = c.column_id
								WHERE ixc.object_id = six.object_id 
									AND ixc.index_id = six.index_id 
									AND ixc.is_included_column = 0
								ORDER BY ixc.index_column_id
								FOR XML PATH ('''')), 1,2,'''')
					, STUFF((SELECT N'', '' + QUOTENAME(c.name)
								FROM sys.index_columns as ixc 
									INNER JOIN sys.columns as c
										ON ixc.object_id = c.object_id
											AND ixc.column_id = c.column_id
								WHERE ixc.object_id = six.object_id 
									AND ixc.index_id = six.index_id 
									AND ixc.is_included_column = 1
								ORDER BY ixc.index_column_id
								FOR XML PATH ('''')), 1,2,'''')
					, six.filter_definition 
					, QUOTENAME(DB_NAME())
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) AS TableName
					, six.index_id		
					, p.partition_number		
					, six.name
					, six.type_desc
					, CASE WHEN six.is_primary_key = 1	THEN ''Yes'' WHEN six.is_primary_key = 0	THEN  ''No'' END
					, CASE WHEN six.is_unique = 1		THEN ''Yes'' WHEN six.is_unique = 0			THEN  ''No'' END AS is_unique
					, CASE WHEN six.is_disabled = 1		THEN ''Yes'' WHEN six.is_disabled = 0		THEN  ''No'' END AS is_disabled
					, p3.row_count
					, ( p3.reserved_page_count * 8 ) / 1024. 
					, ( p3.used_page_count * 8 ) / 1024. 
					, six.fill_factor
					, ius3.user_seeks
					, ius3.user_scans
					, ius3.user_lookups
					, ius3.user_updates
					, d.name AS filegroup_desc
					, p.data_compression_desc

				FROM sys.spatial_indexes AS six
					INNER JOIN sys.objects AS o 
						ON o.object_id = six.object_id
				-- Spatial indexes are stored as INTERNAL TABLES
					INNER JOIN sys.internal_tables AS it
						ON it.parent_object_id = six.object_id
							AND it.parent_minor_id = six.index_id
				-- Workaround to get the correct object_id, index_id to get partition_stats and usage_stats
					INNER JOIN sys.indexes AS ix3
						ON ix3.name = six.name 
							AND ix3.object_id = it.object_id
					INNER JOIN sys.data_spaces AS d
						ON d.data_space_id = six.data_space_id
					INNER JOIN sys.spatial_index_tessellations as sixt
						ON sixt.object_id = six.object_id
							AND sixt.index_id = six.index_id
					INNER JOIN sys.dm_db_partition_stats AS p3
						ON p3.object_id = ix3.object_id 
							and p3.index_id = ix3.index_id
					INNER JOIN sys.partitions as p
						ON p.object_id = ix3.object_id 
							and p.index_id = ix3.index_id
							AND p.partition_number = p3.partition_number
					LEFT JOIN sys.dm_db_index_usage_stats AS ius3
						ON ix3.object_id = ius3.object_id 
							AND ix3.index_id = ius3.index_id
							AND ius3.database_id = DB_ID()

				WHERE o.type = ''U''
					AND o.is_ms_shipped <> 1
					AND o.name LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, o.name)
					AND SCHEMA_NAME(o.schema_id) LIKE ISNULL(@schemaName COLLATE DATABASE_DEFAULT, SCHEMA_NAME(o.schema_id))

					--AND ( ISNULL(@tableName COLLATE DATABASE_DEFAULT, '''') = '''' OR o.name LIKE @tableName )
					--AND ( ISNULL(@schemaName COLLATE DATABASE_DEFAULT, '''') = '''' OR SCHEMA_NAME(o.schema_id) LIKE @schemaName )

			UNION ALL 

			-- Get FULLTEXT indexes
			SELECT 	N''DROP FULLTEXT INDEX ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + N''.'' + QUOTENAME(o.name) AS DROP_INDEX_STATEMENT
					, N''CREATE FULLTEXT INDEX ON '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + N''.'' + QUOTENAME(o.name) + N''('' + 
							( SELECT STUFF( (SELECT N'', '' + c.name + N'' LANGUAGE '' + QUOTENAME(ftl.name)
									FROM sys.fulltext_index_columns AS ftc
										INNER JOIN sys.columns AS c
											ON c.object_id = ftc.object_id
												AND c.column_id = ftc.column_id
										INNER JOIN sys.fulltext_languages AS ftl
											ON ftl.lcid = ftc.language_id
									WHERE ftc.object_id = o.object_id
									FOR XML PATH('''')), 1, 2, '''') ) + N'')'' + CHAR(10) + 
						N''KEY INDEX '' + QUOTENAME(ix.name) + N'' ON ('' + QUOTENAME(ftc.name) + N'', FILEGROUP '' + QUOTENAME(d.name) + N'')'' + CHAR(10) + 
						N''WITH CHANGE_TRACKING '' + ftix.change_tracking_state_desc COLLATE DATABASE_DEFAULT
			
						AS CREATE_INDEX_STATEMENT			

					, STUFF((SELECT N'', '' + QUOTENAME(c.name)
								FROM sys.fulltext_index_columns as ftixc 									
									INNER JOIN sys.columns AS c
										ON c.object_id = ftixc.object_id
											AND c.column_id = ftixc.column_id
								WHERE ftixc.object_id = ftix.object_id 
								ORDER BY ftixc.column_id
								FOR XML PATH ('''')),1,2,'''')
					, NULL AS included_columns
					, NULL AS filter_definition 

					, QUOTENAME(DB_NAME())
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) AS TableName
					, ftix.unique_index_id				
					, p.partition_number
					, ''FULLTEXT INDEX'' AS name
					, ''FULLTEXT'' AS type_desc
					, ''No''
					, ''No''
					, CASE WHEN ftix.is_enabled = 1		THEN ''No'' WHEN ftix.is_enabled = 0	THEN  ''Yes'' END AS is_disabled
					, fulltext_index_partition_stats.row_count
					, fulltext_index_partition_stats.data_size / 1024. / 1024.
					, fulltext_index_partition_stats.data_size / 1024. / 1024.
					, NULL AS fill_factor
					, NULL AS user_seeks
					, NULL AS user_scans
					, NULL AS user_lookups
					, NULL AS user_updates
					, d.name AS filegroup_desc
					, p.data_compression_desc

				FROM sys.fulltext_indexes AS ftix
					LEFT JOIN sys.objects AS o
						ON ftix.object_id = o.object_id
					LEFT JOIN (SELECT table_id AS object_id
										, SUM(data_size) AS data_size
										, SUM(row_count) AS row_count
									 FROM sys.fulltext_index_fragments
									 GROUP BY table_id) AS fulltext_index_partition_stats
						ON fulltext_index_partition_stats.object_id = o.object_id
					LEFT JOIN sys.indexes AS ix
						ON ix.object_id = ftix.object_id
							AND ix.index_id = 1
					LEFT JOIN sys.fulltext_catalogs AS ftc
						ON ftc.fulltext_catalog_id = ftix.fulltext_catalog_id
					LEFT JOIN sys.data_spaces AS d
						ON d.data_space_id = ftix.data_space_id

					LEFT JOIN sys.partitions AS p 
						ON p.object_id = ix.object_id 
							AND p.index_id = ix.index_id

				WHERE o.type = ''U''
					AND o.is_ms_shipped <> 1
					AND o.name LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, o.name)
					AND SCHEMA_NAME(o.schema_id) LIKE ISNULL(@schemaName COLLATE DATABASE_DEFAULT, SCHEMA_NAME(o.schema_id))

					--AND ( ISNULL(@tableName COLLATE DATABASE_DEFAULT, '''') = '''' OR o.name LIKE @tableName )
					--AND ( ISNULL(@schemaName COLLATE DATABASE_DEFAULT, '''') = '''' OR SCHEMA_NAME(o.schema_id) LIKE @schemaName )

				--ORDER BY DatabaseName
				--		, TableName
				--		, is_primary_key DESC
				--		, index_id 

		' )

		--SELECT @sqlString

		INSERT INTO #result
			EXEC sp_executesql @sqlString
					, N'@sortInTempdb NVARCHAR(3), @dropExisting NVARCHAR(3), @online NVARCHAR(3), @maxdop TINYINT'
					, @sortInTempdb			= @sortInTempdb
					, @dropExisting			= @dropExisting
					, @online				= @online
					, @maxdop				= @maxdop

		-- Dummy Line to get statements commented out
		--INSERT INTO #result (DROP_INDEX_STATEMENT, CREATE_INDEX_STATEMENT, dbname)
		--	SELECT  char(10) + '*/'
		--			, char(10) + '*/'
		--			, QUOTENAME(@dbname)

		SET @countDB = @countDB + 1
	END

	-- Time to retrieve all data collected
	SELECT dbname
			, tableName
			, index_name
			, partition_number
			, index_type
			, filegroup_desc
			, is_disabled
			, is_primary_key
			, is_unique
			, [index_columns]
			, included_columns
			, filter
			, row_count
			, size_MB
			, fill_factor
			, reserved_MB
			, data_compression_desc
			, user_seeks
			, user_scans
			, user_lookups
			, user_updates
			, DROP_INDEX_STATEMENT
			, CREATE_INDEX_STATEMENT
		FROM #result
		ORDER BY dbname
			, tableName
			, is_primary_key DESC
			, CASE 
					WHEN @sortOrder = 'index_id'		THEN index_id
					WHEN @sortOrder = 'size_MB'			THEN size_MB
					WHEN @sortOrder = 'user_seeks'		THEN user_seeks
					WHEN @sortOrder = 'user_scans'		THEN user_scans
					WHEN @sortOrder = 'user_lookups'	THEN user_lookups
					WHEN @sortOrder = 'user_updates'	THEN user_updates
					ELSE NULL
				END 
			, CASE 
					WHEN @sortOrder = 'index_id'		THEN partition_number
					ELSE NULL
				END 
			, CASE 
					WHEN @sortOrder = 'index_columns'	THEN [index_columns]
					ELSE NULL
				END 

	IF @includeTotals = 1 BEGIN

		--SELECT	dbname
		--		, CONVERT( DECIMAL(6,2), SUM(ISNULL(size_MB,0) / 1024.) ) AS unusedIndexSize_GB
		--		, COUNT(index_name) AS total
		--	FROM #result
		--	GROUP BY GROUPING SETS ((dbname), ())
		--	HAVING COUNT(index_name) > 0

		;WITH cte AS(
			SELECT	dbname
					, tableName
					, CASE WHEN is_primary_key = 'Yes' THEN SUM(size_MB) END AS rows_size_MB
					, CASE WHEN is_primary_key = 'Yes' THEN SUM(reserved_MB) END AS reserved_rows_size_MB
					, CASE WHEN is_primary_key = 'No' THEN SUM(size_MB) END AS index_size_MB
					, CASE WHEN is_primary_key = 'No' THEN SUM(reserved_MB) END AS reserved_index_size_MB
				FROM #result
				WHERE tableName IS NOT NULL
				GROUP BY dbname, tableName, is_primary_key
		)

		SELECT	a.dbname
				, a.tableName
				, a.rows_size_MB
				, b.index_size_MB
				, ISNULL(a.rows_size_MB, 0) + ISNULL(b.index_size_MB, 0) AS Total_Size_MB
				, a.reserved_rows_size_MB
				, b.reserved_index_size_MB
				, ISNULL(a.reserved_rows_size_MB, 0) + ISNULL(b.reserved_index_size_MB, 0) AS Total_Reserved_MB
			FROM cte AS a
				INNER JOIN cte AS b
					ON a.dbname = b.dbname
						AND a.tableName = b.tableName
			WHERE a.rows_size_MB IS NOT NULL
				AND b.index_size_MB IS NOT NULL


		;WITH cte AS(
			SELECT	dbname
					, CASE WHEN is_primary_key = 'Yes' THEN SUM(size_MB) END AS rows_size_MB
					, CASE WHEN is_primary_key = 'Yes' THEN SUM(reserved_MB) END AS reserved_rows_size_MB
					, CASE WHEN is_primary_key = 'No' THEN SUM(size_MB) END AS index_size_MB
					, CASE WHEN is_primary_key = 'No' THEN SUM(reserved_MB) END AS reserved_index_size_MB
				FROM #result
				WHERE tableName IS NOT NULL
				GROUP BY dbname, is_primary_key
		)

		SELECT	a.dbname
				, a.rows_size_MB
				, b.index_size_MB
				, ISNULL(a.rows_size_MB, 0) + ISNULL(b.index_size_MB, 0) AS Total_Size_MB
				, a.reserved_rows_size_MB
				, b.reserved_index_size_MB
				, ISNULL(a.reserved_rows_size_MB, 0) + ISNULL(b.reserved_index_size_MB, 0) AS Total_Reserved_MB
			FROM cte AS a
				INNER JOIN cte AS b
					ON a.dbname = b.dbname
			WHERE a.rows_size_MB IS NOT NULL
				AND b.index_size_MB IS NOT NULL

	END

	DROP TABLE #result	

END
GO
