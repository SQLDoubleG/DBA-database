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
--				
-- Assupmtions:	
--
-- Change Log:	07/05/2014	RAG	- Created
-- 				07/09/2020	RAG	- Changed Included columns order to be alphabetical
--				14/01/2021	RAG	- Added parameter @EngineEdition
--				22/01/2021	RAG	- Changed the column [included_columns] 
--									to display them in alphabetical order like the create statement
--								- Removed database name from the object name
--				25/02/2021	RAG	- Changes:
--									- Added parameter @schemaName
--									- Removed old code to calculate column cardinality as it wasn't used
--									- Changed to LEFT JOIN on sys.dm_db_missing_index_group_stats as some indexes do not have a matching row there
--
-- =============================================
DECLARE @dbname				SYSNAME		= NULL
		, @schemaName		SYSNAME		= NULL
		, @tableName		SYSNAME		= NULL
		, @sortInTempdb		NVARCHAR(3)	= 'ON'	-- Set to ON to reduce creation time, watch tempdb though!!!
		, @online			NVARCHAR(3)	= 'ON'	-- Set to ON to avoid table locks
		, @maxdop			TINYINT		= 0		-- 0 to use the actual number of processors or fewer based on the current system workload
		, @EngineEdition	INT			= CONVERT(INT, SERVERPROPERTY('EngineEdition'))

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END
	
SET NOCOUNT ON

SET @sortInTempdb	= ISNULL(@sortInTempdb, 'ON')
SET @online			= CASE WHEN SERVERPROPERTY('EngineEdition') >= 3 THEN ISNULL(@online, 'ON') ELSE 'OFF' END
SET @maxdop			= ISNULL(@maxdop, 0)

IF OBJECT_ID('tempdb..#databases') 		IS NOT NULL DROP TABLE #databases
IF OBJECT_ID('tempdb..#mix') 			IS NOT NULL DROP TABLE #mix

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

DECLARE @sqlString	NVARCHAR(MAX)
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
				, QUOTENAME(PARSENAME(mix.statement, 2)) + '.' + QUOTENAME(PARSENAME(mix.statement, 1)) AS table_name
				, NULL AS row_count
				, NULL AS TotalSpaceMB
				, NULL AS DataSpaceMB
				, NULL AS IndexSpaceMB
				, equality_columns 
				, inequality_columns
				, STUFF((SELECT ', ' + QUOTENAME(column_name) 
							FROM sys.dm_db_missing_index_columns(mix.index_handle)
							WHERE column_usage = 'INCLUDE'
							ORDER BY column_name
							FOR XML PATH('')), 1, 2, '') AS included_columns
			FROM sys.dm_db_missing_index_details AS mix
				INNER JOIN #databases AS db
					ON db.database_id = mix.database_id
				
			WHERE (@schemaName IS NULL OR PARSENAME(mix.statement, 2) LIKE @schemaName)
				AND (@tableName IS NULL OR PARSENAME(mix.statement, 1) LIKE @tableName)
	
	WHILE @countDB <= @numDB BEGIN
		
		SET @dbname = (SELECT database_name from #databases WHERE ID = @countDB)


	SET @sqlString = CASE WHEN @EngineEdition <> 5 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
			+ N'
		
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
		'

		--PRINT @sqlstring
		EXEC sp_executesql @sqlstring

		SET @countDB = @countDB + 1

	END
END

SELECT mix.database_name
		, REPLACE(mix.object_name, QUOTENAME(mix.database_name) + '.','') AS object_name
		, row_count
		, TotalSpaceMB
		, DataSpaceMB
		, IndexSpaceMB
		, ISNULL(mix.equality_columns, '') AS equality_columns
		, ISNULL(mix.inequality_columns, '') AS inequality_columns
		, ISNULL(mix.included_columns, '') AS included_columns

		, mixgs.avg_user_impact
		, mixgs.user_seeks
		, mixgs.user_scans
		, mixgs.avg_total_user_cost		

		, 'USE ' + QUOTENAME(mix.database_name) + CHAR(10) + 'GO' + CHAR(10) + 
			'CREATE INDEX ' + 
			QUOTENAME('IX_' + mix.table_name + '_'
				+
			-- Index name
			REPLACE(REPLACE(REPLACE((ISNULL(mix.equality_columns, '') +', '+ ISNULL(mix.inequality_columns, '')), '[', ''), ']', ''), ', ', '_')
			+ '_' + LEFT(CONVERT(NVARCHAR(50), NEWID()), 8)) + 
			CHAR(10) + CHAR(9) + 'ON ' + mix.object_name + ' (' + 
			CASE 
				WHEN ISNULL(mix.equality_columns, '') + ISNULL(', ' + mix.inequality_columns, '') NOT LIKE ',%' 
					THEN ISNULL(mix.equality_columns, '') + ISNULL(', ' + mix.inequality_columns, '')
				ELSE mix.inequality_columns
			END 
			
			+ ')' + 
			-- INCLUDE clause
			ISNULL((CHAR(10) + CHAR(9) + 'INCLUDE (' + mix.included_columns + ')'), '') 
			+ 
			CHAR(10) + CHAR(9) + 
			'WITH (SORT_IN_TEMPDB = '	+ @sortInTempdb + 
			', ONLINE = '	+ @online + 
			', MAXDOP = '	+ CONVERT(NVARCHAR, @maxdop) + ')' AS CREATE_STATEMENT
	FROM #mix AS mix
		INNER JOIN sys.dm_db_missing_index_groups AS mixg
			ON mixg.index_handle = mix.index_handle
		LEFT JOIN sys.dm_db_missing_index_group_stats AS mixgs
			ON mixgs.group_handle = mixg.index_group_handle
	ORDER BY mix.database_name
			, mix.object_name
			, mixgs.avg_user_impact DESC
GO