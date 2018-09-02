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
-- Create date: 18/09/2013
-- Description:	Returns statistics for nullable columns in a given database or all databases
--				This info can be useful to determine if the column can benefit from SPARSE functionality
--
-- Change Log:	24/09/2013 RAG Added parameter @tableName
--				24/09/2013 RAG Added parameter @includeVarLenghtColumns to filter variable length columns
--				30/09/2013 RAG Added parameter @colName to filter by column if required
-- =============================================
CREATE PROCEDURE [dbo].[DBA_nullableColumnsStats]
	@dbname						SYSNAME = NULL
	, @tableName				SYSNAME = NULL
	, @colName					SYSNAME = NULL
	, @debugging				BIT = 0
	, @includeVarLenghtColumns	BIT = 0
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @sql	NVARCHAR(MAX)

	IF @dbname IS NULL BEGIN SET @debugging = 1 END

	--SET @tableName					= ISNULL(@tableName, '')
	--SET @colName					= ISNULL(@colName, '')
	SET @debugging					= ISNULL(@debugging, 0)
	SET @includeVarLenghtColumns	= ISNULL(@includeVarLenghtColumns, 0)

	IF ISNULL(@tableName, '') <> '' AND ISNULL(@colName, '') <> '' BEGIN SET @includeVarLenghtColumns = 1 END
	
	CREATE TABLE #allDatabases(
		ID				INT IDENTITY
		, name			SYSNAME
	)
	
	CREATE TABLE #result(
		DatabaseName	SYSNAME
		, SchemaName	SYSNAME
		, TableName		SYSNAME
		, ColumnName	SYSNAME
		, DataType		SYSNAME
		, [maxLength]	SYSNAME
		, [length]		SYSNAME
		, Nullability	VARCHAR(8)
		, RowsInTable	BIGINT
		, RowsInValue	BIGINT
		, Percentage	DECIMAL(10,2)
	)

	CREATE TABLE #resultDebugging(
		ID				INT
		, DatabaseName SYSNAME
		, object_id		INT
		, TableName	SYSNAME
		, SchemaName	SYSNAME
		, total_rows	INT
		, column_id		INT
		, ColumnName	SYSNAME
		, dataType		SYSNAME
		, max_length	INT
		, length		INT
		, sql			VARCHAR(4000)
	)

	DECLARE @numDBs		INT
			, @countDBs INT = 1
	
	INSERT INTO #allDatabases
		SELECT name 
			FROM sys.databases AS d
			WHERE database_id > 4
				AND d.state = 0
				AND d.name LIKE ISNULL(@dbname, d.name)

	SET @numDBs = @@ROWCOUNT

	WHILE @countDBs <= @numDBs BEGIN

		SELECT @dbname = name
			FROM #allDatabases
			WHERE ID = @countDBs

		SET @sql = N'
			
			USE ' + QUOTENAME(@dbname) + N'
		
			DECLARE @tableName					SYSNAME = ' + CASE WHEN ISNULL(@tableName, '')	= '' THEN 'NULL' ELSE '''' + @tableName + '''' END + '
			DECLARE @colName					SYSNAME = ' + CASE WHEN ISNULL(@colName, '')	= '' THEN 'NULL' ELSE '''' + @colName + '''' END + '
			
			DECLARE @debugging					BIT = ' + CONVERT(CHAR(1), @debugging) + '
			DECLARE @includeVarLenghtColumns	BIT = ' + CONVERT(CHAR(1), @includeVarLenghtColumns) + CONVERT(NVARCHAR(MAX), '

			DECLARE @numColumns		INT
					, @countColumns	INT = 1
					, @sql			NVARCHAR(4000)

			CREATE TABLE #allColumns(
					ID				INT IDENTITY PRIMARY KEY
					, DatabaseName SYSNAME
					, object_id		INT
					, TableName	SYSNAME
					, SchemaName	SYSNAME
					, total_rows	INT
					, column_id		INT
					, ColumnName	SYSNAME
					, dataType		SYSNAME
					, max_length	INT
					, length		INT
					, sql			VARCHAR(4000)
			)

			CREATE TABLE #dataTypes(
					user_type_id	INT
					, name			SYSNAME
			)

			INSERT INTO #dataTypes
				SELECT user_type_id
						, name
					FROM sys.types WHERE name NOT IN (''varchar'', ''nvarchar'', ''text'', ''ntext'', ''varbinary'' )

			INSERT INTO #allColumns
						(DatabaseName
						, object_id
						, TableName
						, SchemaName
						, total_rows
						, column_id
						, ColumnName
						, dataType
						, max_length
						, length
						, sql)
				SELECT TOP 100 PERCENT 
						QUOTENAME(DB_NAME())
						, t.object_id
						, QUOTENAME(t.name)
						, QUOTENAME(SCHEMA_NAME(t.schema_id))
						, SUM(st.row_count)
						, c.column_id
						, QUOTENAME(c.name)
						, ty.name
						, c.max_length
						, CONVERT(INT, c.max_length * CASE WHEN ty.variable = 1 THEN CONVERT(DECIMAL(6,2), ty.prec) / ty.[length] ELSE 1 END ) AS lenght
						, 

						''SELECT '''''' + QUOTENAME(DB_NAME()) + ''''''  AS [DatabaseName]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '''''' AS [SchemaName]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + QUOTENAME(t.name) + '''''' AS [TableName]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + QUOTENAME(c.name) + '''''' AS [ColumnName]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + ty.name + '''''' AS [DataType]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + CONVERT(NVARCHAR(4),c.max_length) + '''''' AS [DataLength]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + CONVERT(NVARCHAR(4),CONVERT(INT, c.max_length * CASE WHEN ty.variable = 1 THEN CONVERT(DECIMAL(6,2), ty.prec) / ty.[length] ELSE 1 END )) + '''''' AS [Length]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', CASE WHEN '' + QUOTENAME(c.name) + '' IS NULL THEN ''''NULL'''' ELSE ''''NOT NULL'''' END AS [Nullability]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', '''''' + CONVERT(NVARCHAR(16),SUM(st.row_count)) + '''''' AS [RowsInTable]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', COUNT (1) AS [RowsInValue]'' + CHAR(10) +
						REPLICATE(CHAR(9), 2) + '', CONVERT(DECIMAL(10,2), (COUNT(1) * 100.) / '' + CONVERT(NVARCHAR(16),SUM(st.row_count)) + '') AS [Percentage]'' + CHAR(10) +
						REPLICATE(CHAR(9), 1) + ''FROM '' + QUOTENAME(DB_NAME()) + ''.'' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name) + '' '' + CHAR(10) +
						REPLICATE(CHAR(9), 1) + ''GROUP BY CASE WHEN '' + QUOTENAME(c.name) + '' IS NULL THEN ''''NULL'''' ELSE ''''NOT NULL'''' END'' AS sql

					FROM sys.tables AS t
						INNER JOIN sys.columns AS c
							ON c.object_id = t.object_id
						INNER JOIN sys.systypes AS ty
							ON ty.xusertype = c.user_type_id
						INNER JOIN sys.dm_db_partition_stats AS st
							ON st.object_id = t.object_id 
								AND (st.index_id < 2)
					WHERE is_ms_shipped		<> 1 -- To avoid replication tables
						AND c.is_nullable	= 1	-- Only NULLable columns 
						AND c.is_sparse		= 0	-- which are not SPARSE already
						AND c.is_computed	= 0	-- And are Non computed columns
						AND t.name LIKE ISNULL(@tableName, t.name)
						AND c.name LIKE ISNULL(@colName, c.name)
						AND ( (@includeVarLenghtColumns = 0 AND c.user_type_id IN (SELECT user_type_id FROM #dataTypes)) 
							OR @includeVarLenghtColumns = 1 )					
					GROUP BY t.object_id
						, t.name
						, t.schema_id
						, c.column_id
						, c.name
						, ty.name
						, c.max_length
						, CONVERT(INT, c.max_length * CASE WHEN ty.variable = 1 THEN CONVERT(DECIMAL(6,2), ty.prec) / ty.[length] ELSE 1 END ) 
					ORDER BY t.name, c.column_id ASC
			
			SET @numColumns = @@ROWCOUNT

			IF @debugging = 1 BEGIN 
				SELECT * FROM #allColumns
			END
			ELSE BEGIN
				WHILE @countColumns <= @numColumns BEGIN
					
					SELECT sql FROM #allColumns WHERE ID = @countColumns 

					SELECT @sql = sql
						FROM #allColumns
						WHERE ID = @countColumns 

					EXECUTE sp_executesql @sql
					SET @countColumns = @countColumns + 1
				END
			END
			
			DROP TABLE #allColumns
			DROP TABLE #dataTypes
		')

		IF @debugging = 0 BEGIN 
			INSERT INTO #result
			EXECUTE sp_executesql @sql
		END
		ELSE BEGIN
			INSERT INTO #resultDebugging
			EXECUTE sp_executesql @sql
		END

		SET @countDBs = @countDBs + 1
	END

	IF ISNULL(@debugging, 0) = 0 BEGIN 
		SELECT DatabaseName
				, SchemaName
				, TableName
				, ColumnName
				, DataType
				, [length]
				, CASE 
					WHEN Nullability = 'NULL' THEN CONVERT( VARCHAR(10), CONVERT( DECIMAL(10,2), ([maxLength] * RowsInValue) / 1024. / 1024 ) )
					ELSE ''
				END AS SpaceUsed_MB
				, Nullability
				, RowsInTable
				, RowsInValue
				--, CONVERT(DECIMAL(10,2), (RowsInValue * 100. ) / RowsInTable) AS Percentage
				, Percentage
				, CASE 
					WHEN Nullability = 'NULL' THEN 
						'ALTER TABLE ' + TableName + ' ALTER COLUMN ' + ColumnName + ' ' + UPPER(DataType) + '(' + CONVERT(VARCHAR(4),[length]) + ') SPARSE NULL' + CHAR(10) + 'GO' + CHAR(10) +
						'ALTER TABLE ' + TableName + ' REBUILD' 
					ELSE ''
				END AS ALTER_TABLE
			FROM #result 
			ORDER BY DatabaseName
				, TableName
				, ColumnName
				, Nullability
	END
	ELSE BEGIN
		SELECT DatabaseName	
				, SchemaName
				, TableName		
				, ColumnName	
				, dataType
				, max_length	
				, Sql
			FROM #resultDebugging
	END

	DROP TABLE #result
	DROP TABLE #allDatabases
	DROP TABLE #resultDebugging
END




GO
