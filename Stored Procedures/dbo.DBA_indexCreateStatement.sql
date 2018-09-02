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
-- Create date: 04/06/2014
-- Description:	Returns CREATE INDEX statements for given columns
--				Index columns are returned as per BOL http://technet.microsoft.com/en-us/library/ms345434.aspx
--					Equality columns should be put before the inequality columns, and together they should make the key of the index. 
--					Included columns should be added to the CREATE INDEX statement using the INCLUDE clause. 
--					To determine an effective order for the equality columns, order them based on their selectivity: 
--					list the most selective columns first (leftmost in the column list).
--				The order is calculated based on column statistics.
--				
-- Assupmtions:	
--
-- Change Log:	04/06/2014 RAG Created
--				
-- =============================================
CREATE PROCEDURE [dbo].[DBA_indexCreateStatement] 
	@dbname						SYSNAME
	, @tableName				SYSNAME
	, @equalityColumnsList		NVARCHAR(1000)
	, @inequalityColumnsList	NVARCHAR(1000) 
	, @includedColumnsList		NVARCHAR(1000)
	, @sortInTempdb				NVARCHAR(3)	= 'ON'	-- Set to ON to reduce creation time, watch tempdb though!!!
	, @maxdop					TINYINT		= 0
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @sql				NVARCHAR(MAX)

	SET @sortInTempdb	= ISNULL(@sortInTempdb, 'ON')
	SET @maxdop			= ISNULL(@maxdop, 0)

	IF NOT EXISTS ( SELECT 1 FROM sys.databases WHERE name = ISNULL(@dbname, '') ) BEGIN
		RAISERROR ( 'The database specified does not exists in this server', 16, 0, 0 )
		RETURN -100
	END

	CREATE TABLE #mix(
		object_name			SYSNAME
		, row_count			INT NULL
		, TotalSpaceMB		DECIMAL(10,2) NULL
		, DataSpaceMB		DECIMAL(10,2) NULL
		, IndexSpaceMB		DECIMAL(10,2) NULL
	)

	CREATE TABLE #mixc(
		ID					INT IDENTITY(1,1)
		, column_id			INT		NULL
		, column_name		SYSNAME 
		, column_usage		SYSNAME NULL
		, stats_name		SYSNAME NULL
		, All_Density		FLOAT NULL
	)

	CREATE TABLE #stats_density(
		column_id			INT
		, All_Density		FLOAT
		, Average_Length	INT
		, Columns			NVARCHAR(4000)
	)

	INSERT INTO #mixc (column_name)
		EXECUTE DBA.dbo.DBA_parseDelimitedString @equalityColumnsList
	UPDATE #mixc SET column_usage = 'EQUALITY' WHERE column_usage IS NULL

	INSERT INTO #mixc (column_name)
		EXECUTE DBA.dbo.DBA_parseDelimitedString @inequalityColumnsList
	UPDATE #mixc SET column_usage = 'INEQUALITY' WHERE column_usage IS NULL

	INSERT INTO #mixc (column_name)
		EXECUTE DBA.dbo.DBA_parseDelimitedString @includedColumnsList
	UPDATE #mixc SET column_usage = 'INCLUDE' WHERE column_usage IS NULL

	-- If there is an included column which is also in the list of EQ or INEQ
	DELETE m1
		FROM #mixc as m1
			INNER JOIN #mixc AS m2
				ON m2.column_name = m1.column_name
					AND m2.column_usage <> m1.column_usage
		WHERE m1.column_usage = 'INCLUDE'


	SET @sql = N'
		USE ' + QUOTENAME(@dbname) + N'	

		DECLARE @table_name		SYSNAME = ' + '''' + @tableName + '''' + CONVERT( NVARCHAR(MAX), N'	
		DECLARE @count_ix		INT = 1
		DECLARE @column_name	SYSNAME
		DECLARE @stats_name		SYSNAME
		DECLARE @column_id		INT		
		DECLARE @dbcc			NVARCHAR(1000)

		IF OBJECT_ID(@table_name) IS NULL BEGIN
			RAISERROR ( ''The table specified does not exists in this database'', 16, 0, 0 )
			RETURN
		END

		IF EXISTS (SELECT 1 FROM #mixc WHERE COLUMNPROPERTY(OBJECT_ID(@table_name), column_name, ''ColumnId'') IS NULL) BEGIN
			RAISERROR ( ''Any of the columns specified does not exists in this table'', 16, 0, 0 )
			RETURN
		END

		-- Table information
		INSERT INTO #mix
			SELECT object_name	= t.name
					, row_count		= MAX(p.rows)
					, TotalSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(a.used_pages)) / 1024 , 0 ) )
					, DataSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(               CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) ) 
					, IndexSpaceMB	= CONVERT( DECIMAL(10,2), ISNULL( (8.000000 * SUM(a.used_pages - CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) )
				FROM sys.tables AS t
					INNER JOIN sys.indexes AS i 
						ON t.object_id = i.object_id
					INNER JOIN sys.partitions AS p 
						ON p.object_id = i.object_id
							AND p.index_id = i.index_id
					INNER JOIN sys.allocation_units AS a 
						ON a.container_id = p.partition_id 
				WHERE t.object_id = OBJECT_ID(@table_name)
				GROUP BY t.name

		UPDATE mixc
			SET column_id = c.column_id
			FROM #mixc AS mixc
				LEFT JOIN sys.columns AS c
					ON c.name COLLATE DATABASE_DEFAULT = mixc.column_name COLLATE DATABASE_DEFAULT
				WHERE c.object_id = OBJECT_ID(@table_name)
		
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
				AND stc.object_id = OBJECT_ID(@table_name)
		)

		UPDATE mixc
			SET stats_name = cte.name
			FROM #mixc AS mixc
			INNER JOIN cte
				ON cte.column_id = mixc.column_id
			WHERE rowNumber = 1
		
		SET @count_ix = ( SELECT MIN(ID) FROM #mixc WHERE column_usage IN (''EQUALITY'', ''INEQUALITY'') )

		WHILE @count_ix IS NOT NULL BEGIN
			
			TRUNCATE TABLE #stats_density

			SELECT @column_id		= column_id
					, @column_name	= column_name
					, @stats_name	= stats_name
				FROM #mixc
				WHERE ID = @count_ix

			SET @dbcc = ''DBCC SHOW_STATISTICS ('''''' + @table_name + '''''', '''''' + @stats_name + '''''') WITH NO_INFOMSGS, DENSITY_VECTOR''

			INSERT INTO #stats_density ( All_Density, Average_Length, Columns )
				EXECUTE sp_executesql @dbcc

			UPDATE #mixc
				SET All_Density = (SELECT All_Density FROM #stats_density WHERE Columns = @column_name )
				WHERE ID = @count_ix

			SET @count_ix = ( SELECT MIN(ID) FROM #mixc WHERE column_usage IN (''EQUALITY'', ''INEQUALITY'') AND ID > @count_ix )

		END

	')

	EXEC sp_executesql @sql

	SELECT @dbname AS database_name
			, [object_name]
			, row_count
			, TotalSpaceMB
			, DataSpaceMB
			, IndexSpaceMB
			, 'USE ' + QUOTENAME(@dbname) + CHAR(10) + 'GO' + CHAR(10) + 
				'CREATE INDEX ' + 
				QUOTENAME('IX_' + @tableName +
				+
				-- Index name
				(SELECT '_' + column_name 
						FROM #mixc AS r
						WHERE r.column_usage IN ('EQUALITY', 'INEQUALITY')
						ORDER BY column_usage ASC
								, All_Density ASC
						FOR XML PATH('')) + '_' + LEFT(CONVERT(NVARCHAR(50), NEWID()), 8))
				+ 
				CHAR(10) + CHAR(9) + 'ON ' + @tableName + ' ('
				+
				-- ON clause
				STUFF((SELECT ', ' + QUOTENAME(column_name) 
							FROM #mixc AS r
						WHERE r.column_usage IN ('EQUALITY', 'INEQUALITY')
						ORDER BY column_usage ASC
								, All_Density ASC
							FOR XML PATH('')), 1, 2, '') + ')' 
				+ 
				-- INCLUDE clause
				ISNULL((CHAR(10) + CHAR(9) + 'INCLUDE (' + 
					STUFF((SELECT ', ' + QUOTENAME(column_name) 
								FROM #mixc AS r
								WHERE r.column_usage = 'INCLUDE'
								ORDER BY All_Density ASC
								FOR XML PATH('')), 1, 2, '') + ')'), '') 
				+ 
				CHAR(10) + CHAR(9) + 
				'WITH (SORT_IN_TEMPDB = '	+ @sortInTempdb + 				
				', MAXDOP = '	+ CONVERT(NVARCHAR, @maxdop) + ')' AS CREATE_STATEMENT
		FROM #mix
END 




GO
