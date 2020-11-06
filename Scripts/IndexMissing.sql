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
-- Create date: 07/05/2014
-- Description:	Returns CREATE statements for missing indexes within a database or table specified.
--				Index columns are returned as per BOL http://technet.microsoft.com/en-us/library/ms345434.aspx
--					To convert the information returned by sys.dm_db_missing_index_details into a CREATE INDEX statement, 
--					equality columns should be put before the inequality columns, and together they should make the key of the index. 
--					Included columns should be added to the CREATE INDEX statement using the INCLUDE clause. 
--					To determine an effective order for the equality columns, order them based on their selectivity: 
--					list the most selective columns first (leftmost in the column list).
--				The order is calculated based on column statistics.
--				
-- Assupmtions:	
--
-- Change Log:	07/05/2014 RAG Created
-- 				07/09/2020 RAG Changed Included columns order to be alphabetical
--				
-- =============================================
DECLARE @dbname			SYSNAME		= NULL
		, @tableName	SYSNAME		= NULL
		, @sortInTempdb	NVARCHAR(3)	= 'ON'	-- Set to ON to reduce creation time, watch tempdb though!!!
		, @online		NVARCHAR(3)	= 'ON'	-- Set to ON to avoid table locks
		, @maxdop		TINYINT		= 0		-- 0 to use the actual number of processors or fewer based on the current system workload
	
SET NOCOUNT ON

SET @sortInTempdb	= ISNULL(@sortInTempdb, 'ON')
SET @online			= CASE WHEN SERVERPROPERTY('EngineEdition') >= 3 THEN ISNULL(@online, 'ON') ELSE 'OFF' END
SET @maxdop			= ISNULL(@maxdop, 0)

-- All missing indexes 
CREATE TABLE #mix(
	database_id				SMALLINT
	, database_name			SYSNAME
	, index_handle			INT
	, object_id				INT
	, object_name			SYSNAME
	, table_name			SYSNAME NULL -- To get only table name and not 3 parts name
	, row_count				INT NULL
	, TotalSpaceMB			DECIMAL(10,2) NULL
	, DataSpaceMB			DECIMAL(10,2) NULL
	, IndexSpaceMB			DECIMAL(10,2) NULL
	, equality_columns		NVARCHAR(4000)
	, inequality_columns	NVARCHAR(4000)
	, included_columns		NVARCHAR(4000)
)

-- All missing indexes columns
CREATE TABLE #mixc(
	index_handle	INT
	, column_id		INT
	, column_name	SYSNAME
	, column_usage	SYSNAME
)
	
CREATE TABLE #stats(
	ID				INT IDENTITY(1,1)
	, database_id	SMALLINT
	, database_name	SYSNAME
	, index_handle	INT
	, object_id		INT
	, object_name	SYSNAME
	, column_id		INT
	, column_name	SYSNAME
	, column_usage	SYSNAME
	, stats_name	SYSNAME
	, All_Density	FLOAT NULL
)

CREATE TABLE #r(
	database_id		SMALLINT
	, database_name	SYSNAME
	, index_handle	INT
	, object_id		INT
	, object_name	SYSNAME
	, column_id		INT
	, column_name	SYSNAME
	, column_usage	SYSNAME
	, All_Density	FLOAT NULL
)

CREATE TABLE #stats_density(
	index_handle	INT
	, column_id		INT
	, All_Density	FLOAT
	, Average_Length INT
	, Columns		NVARCHAR(4000)
)

DECLARE @sql		NVARCHAR(MAX)
		, @countDB	INT = 1
		, @numDB	INT
	
SELECT TOP 100 PERCENT 
		IDENTITY(INT, 1, 1) AS ID
		, database_id
		, name AS database_name
	INTO #databases
	FROM sys.databases 
	WHERE [name] NOT IN ('distribution') 
		AND database_id > 4
		AND state = 0 
		AND name LIKE ISNULL(@dbname, name)
	ORDER BY name ASC		

SET @numDB = @@ROWCOUNT

IF @numDB > 0 BEGIN

	INSERT INTO #mix
		SELECT mix.database_id
				, DB_NAME(mix.database_id) AS database_name
				, mix.index_handle
				, mix.object_id
				, mix.statement as object_name
				, NULL AS table_name
				, NULL AS row_count
				, NULL AS TotalSpaceMB
				, NULL AS DataSpaceMB
				, NULL AS IndexSpaceMB
				, equality_columns 
				, inequality_columns
				, included_columns
			FROM sys.dm_db_missing_index_details AS mix
				INNER JOIN #databases AS db
					ON db.database_id = mix.database_id
	
	INSERT INTO #mixc
		SELECT  mix.index_handle
				, mixc.column_id
				, mixc.column_name
				, mixc.column_usage
			FROM #mix AS mix
				-- This dmv makes problems when compatibility < 90
				CROSS APPLY sys.dm_db_missing_index_columns(mix.index_handle) AS mixc	

	WHILE @countDB <= @numDB BEGIN
		
		SET @dbname = (SELECT database_name from #databases WHERE ID = @countDB)


		SET @sql = N'
			USE ' + QUOTENAME(@dbname) + CONVERT( NVARCHAR(MAX), N'	
		
			DECLARE @count_ix		INT = 1
			DECLARE @num_ix			INT
			DECLARE @table_name		SYSNAME
			DECLARE @column_name	SYSNAME
			DECLARE @stats_name		SYSNAME
			DECLARE @index_handle	INT
			DECLARE @column_id		INT		
			DECLARE @dbcc			NVARCHAR(1000)

			-- Delete info about other objects but the specified one, if any
			DELETE #mix
				WHERE @tableName COLLATE DATABASE_DEFAULT IS NOT NULL
					-- AND object_id <> OBJECT_ID(@tableName)				
					AND OBJECT_NAME(object_id) NOT LIKE @tableName COLLATE DATABASE_DEFAULT
				
			-- Get table information to update 
			;WITH cte AS(
				SELECT mix.index_handle
						, table_name	= t.name
						, row_count		= MAX(p.rows)
						, TotalSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(a.used_pages)) / 1024 , 0 ) )
						, DataSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(               CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) ) 
						, IndexSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(a.used_pages - CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) )
					FROM #mix AS mix
						INNER JOIN sys.tables AS t
							ON t.object_id = mix.object_id
								AND mix.database_id = DB_ID()
						INNER JOIN sys.indexes AS i 
							ON t.object_id = i.object_id
						INNER JOIN sys.partitions AS p 
							ON p.object_id = i.object_id
								AND p.index_id = i.index_id
						INNER JOIN sys.allocation_units AS a 
							ON a.container_id = p.partition_id 
					GROUP BY mix.index_handle
							, t.name
			)

			UPDATE mix
				SET table_name		= cte.table_name
					, row_count		= cte.row_count	
					, TotalSpaceMB	= cte.TotalSpaceMB
					, DataSpaceMB	= cte.DataSpaceMB
					, IndexSpaceMB	= cte.IndexSpaceMB	
				FROM #mix AS mix
					INNER JOIN cte
						ON cte.index_handle = mix.index_handle
				
			TRUNCATE TABLE #stats
		
			-- CTE to get just one statistic per column
			;WITH cte 
			AS (
			SELECT st.object_id
					, st.name
					, stc.column_id
					, ROW_NUMBER() OVER (PARTITION BY st.object_id, stc.column_id ORDER BY stc.column_id, st.auto_created DESC) AS rowNumber
				FROM sys.stats AS st
				INNER JOIN sys.stats_columns as stc
					ON stc.object_id = st.object_id
						AND stc.stats_id = st.stats_id
				WHERE OBJECTPROPERTY(st.object_id, ''IsMSShipped'') = 0
			)

			INSERT INTO #stats
				SELECT mix.database_id
						, mix.database_name
						, mix.index_handle
						, mix.object_id
						, mix.object_name
						, mixc.column_id
						, mixc.column_name
						, mixc.column_usage
						, cte.name AS stats_name
						, NULL AS All_Density
					FROM #mix AS mix
						INNER JOIN #mixc AS mixc
							ON mixc.index_handle = mix.index_handle
					-- stats are at database level, hence the loop through
						INNER JOIN cte
							ON cte.object_id = mix.object_id
								AND cte.column_id = mixc.column_id
					WHERE mix.database_id = DB_ID()
						AND rowNumber = 1
		
			SET @num_ix = @@ROWCOUNT

			WHILE @count_ix <= @num_ix BEGIN
			
				TRUNCATE TABLE #stats_density

				SELECT @index_handle	= index_handle
						, @column_id	= column_id
						, @column_name	= column_name
						, @table_name	= object_name
						, @stats_name	= stats_name
					FROM #stats
					WHERE ID = @count_ix

				SET @dbcc = ''DBCC SHOW_STATISTICS ('''''' + @table_name + '''''', '''''' + @stats_name + '''''') WITH NO_INFOMSGS, DENSITY_VECTOR''

				INSERT INTO #stats_density ( All_Density, Average_Length, Columns )
					EXECUTE sp_executesql @dbcc

				UPDATE #stats
					SET All_Density = (SELECT All_Density FROM #stats_density WHERE Columns = @column_name )
					WHERE ID = @count_ix

				SET @count_ix = @count_ix + 1
			END

			-- The same column can be part of different statistics, so get one row per column
			INSERT INTO #r (database_id, database_name, index_handle, object_id	, object_name, column_id, column_name, column_usage, All_Density)
				SELECT DISTINCT database_id, database_name, index_handle, object_id	, object_name, column_id, column_name, column_usage, All_Density
					FROM #stats

		')

		--PRINT @sql
		EXEC sp_executesql @sql
				, @params = N'@tableName SYSNAME' 
				, @tableName = @tableName 

		SET @countDB = @countDB + 1

	END
END

SELECT mix.database_id
		, mix.database_name
		, mix.object_name
		, row_count
		, TotalSpaceMB
		, DataSpaceMB
		, IndexSpaceMB
		, mix.equality_columns
		, mix.inequality_columns
		, mix.included_columns
		, mixgs.avg_user_impact
		, mixgs.user_seeks
		, mixgs.user_scans
		, mixgs.avg_total_user_cost
		, 'USE ' + QUOTENAME(mix.database_name) + CHAR(10) + 'GO' + CHAR(10) + 
			'CREATE INDEX ' + 
			QUOTENAME('IX_' + mix.table_name +
				+
			-- Index name
			(SELECT '_' + column_name 
					FROM #r AS r
					WHERE r.index_handle = mix.index_handle
						AND r.column_usage IN ('EQUALITY', 'INEQUALITY')
					ORDER BY column_usage ASC
							, All_Density ASC
					FOR XML PATH('')) + '_' + LEFT(CONVERT(NVARCHAR(50), NEWID()), 8))
			+ 
			CHAR(10) + CHAR(9) + 'ON ' + mix.object_name + ' ('
			+
			-- ON clause
			STUFF((SELECT ', ' + column_name 
						FROM #r AS r
						WHERE r.index_handle = mix.index_handle
							AND r.column_usage IN ('EQUALITY', 'INEQUALITY')
						ORDER BY column_usage ASC
								, All_Density ASC
						FOR XML PATH('')), 1, 2, '') + ')' 
			+ 
			-- INCLUDE clause
			ISNULL((CHAR(10) + CHAR(9) + 'INCLUDE (' + 
				STUFF((SELECT ', ' + column_name 
							FROM #r AS r
							WHERE r.index_handle = mix.index_handle
								AND r.column_usage = 'INCLUDE'
							ORDER BY column_name ASC
							FOR XML PATH('')), 1, 2, '') + ')'), '') 
			+ 
			CHAR(10) + CHAR(9) + 
			'WITH (SORT_IN_TEMPDB = '	+ @sortInTempdb + 
			', ONLINE = '	+ @online + 
			', MAXDOP = '	+ CONVERT(NVARCHAR, @maxdop) + ')' AS CREATE_STATEMENT

	FROM #mix AS mix
		INNER JOIN sys.dm_db_missing_index_groups AS mixg
			ON mixg.index_handle = mix.index_handle
		INNER JOIN sys.dm_db_missing_index_group_stats AS mixgs
			ON mixgs.group_handle = mixg.index_group_handle
	ORDER BY mix.database_name
			, mix.object_name
			, mixgs.avg_user_impact DESC

DROP TABLE #databases
DROP TABLE #mix
DROP TABLE #mixc
DROP TABLE #r
DROP TABLE #stats
DROP TABLE #stats_density
GO
