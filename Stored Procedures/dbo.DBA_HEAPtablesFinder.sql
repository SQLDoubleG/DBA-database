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
-- Description:	Find all heap tables in user databases or a given database, 
--				and script out possible actions to create PK on them (to REVIEW and execute manually)
--
--				The script returns 1 resultset
--				- List of tables which are HEAP tables
--					- Database Name
--					- Table Name
--					- Row count 
--					- Size in MB
--					- Has Any Non Clustered Index 
--					- CREATE_PK_STATEMENT, will contain the appropiate actions according the following logic
--						- If there's a Primary Key (NONCLUSTERED), this will be recreated as CLUSTERED
--						- If there's an IDENTITY column a PK CLUSTERED will be created on this column
--						- If there's a column called ID (NOT NULL)
--							- If the column doesnt have any duplicates a PK CLUSTERED will be created on this column
--							- If the column have duplicated values, A new column called newID INT IDENTITY will be added to the table and a PK constraint will be created on this column
--						- If there's a column called ID (NULL) 
--							- If the column doesnt hold any NULL value and doesnt have any duplicates, the column will be altered to NOT NULL and PK CLUSTERED will be created on this column
--							- If the column holds NULL values or has duplicates, a new column called newID INT IDENTITY will be added to the table and a PK constraint will be created on this column
--						- If there's no good candidates, a column called ID INT IDENTITY will be added to the table and a PK constraint will be created on this column
--					** The creation of new columns is in 2 steps to benefit from the option ONLINE = ON
--
-- Log Changes:	19/09/2013 RAG Changed global temporary table for a local to avoid concurrency problems
--				19/09/2013 RAG Included clause [is_ms_shipped <> 1] to avoid tables automatically created by replication processes
-- =============================================
CREATE PROCEDURE [dbo].[DBA_HEAPtablesFinder]
	@dbname			SYSNAME = NULL
AS
BEGIN 

	SET NOCOUNT ON

	CREATE TABLE #result
		(ID						INT IDENTITY(1,1)
		, dbname				SYSNAME NULL
		, tableName				SYSNAME NULL
		, row_count				INT NULL
		, sizeMB				DECIMAL(7,2) NULL
		, hasNonClusteredIndex	VARCHAR(3) NULL
		, CREATE_PK_STATEMENT	NVARCHAR(4000) NULL)

	DECLARE @databases	TABLE 
		(ID			INT IDENTITY(1,1)
		, dbname	SYSNAME
		, files		INT)

	DECLARE @numDB			INT
			, @countDB		INT = 1
			, @sqlString	NVARCHAR(MAX)

	INSERT @databases (dbname)
		SELECT TOP 100 PERCENT
				name 
			FROM sys.databases d 
			WHERE d.name LIKE ISNULL(@dbname, d.name)
				AND d.database_id > 4
				AND d.name NOT LIKE 'ReportServer%'
				AND state = 0 -- Online
			ORDER BY name

	SET @numDB = @@ROWCOUNT;

	WHILE @countDB <= @numDB BEGIN
		SET @dbname = (SELECT dbname from @databases WHERE ID = @countDB)

		INSERT INTO #result (CREATE_PK_STATEMENT)
			SELECT '/*' + char(10) + 'USE ' + @dbname + char(10) + 'GO' 

		SET @sqlString = N'USE ' + QUOTENAME(@dbname) + N'	
			--
			-- Parameters for CREATE INDEX statements, modify at best convenience
			--
			DECLARE	@online		NVARCHAR(3)	= ''ON''	-- Set to ON to avoid table locks

			-- Get HEAP tables within the database
			SELECT	DB_NAME(DB_ID())
					, QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name)
					, p.row_count
					, CONVERT(DECIMAL(7,2), (p.reserved_page_count*8.)/1024.) 
					, CASE WHEN EXISTS ( SELECT 1 
											FROM sys.indexes AS ix2 
											WHERE ix2.object_id = ix.object_id 
												AND ix2.type = 2 ) -- NONCLUSTERED
							THEN ''Yes'' 
							ELSE ''No'' 
						END AS col
					--, ( select top 1 1 from sys.indexes as ix inner join sys.index_columns as ixc on ixc.object_id = ix.object_id and ixc.index_id = ix.index_id where ix.object_id = o.object_id and ix.is_primary_key = 1 ) as case1
					--, ( select 1 from sys.columns as c where c.object_id = o.object_id and ( (c.is_identity = 1) OR (LOWER(c.name) = ''id'' AND c.is_nullable = 0) ) )  as case2
					--, ( select 1 from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 ) as case3
					--, ( select 1 from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' ) as case4
					, 
						CASE	
							-- when there is a PK, but it''s not clustered
							WHEN EXISTS ( select top 1 1 from sys.indexes as ix inner join sys.index_columns as ixc on ixc.object_id = ix.object_id and ixc.index_id = ix.index_id where ix.object_id = o.object_id and ix.is_primary_key = 1 )
								THEN ''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + 
										'' DROP '' + ( select top 1 ix.name from sys.indexes as ix inner join sys.index_columns as ixc on ixc.object_id = ix.object_id and ixc.index_id = ix.index_id inner join sys.columns as c on c.object_id = ixc.object_id and c.column_id = ixc.column_id where ix.object_id = o.object_id and ix.is_primary_key = 1 ) + char(10) + ''GO'' + char(10) +
									''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + 
									'' ADD CONSTRAINT PK_'' + o.name + ''_ID'' + '' PRIMARY KEY CLUSTERED ('' + STUFF( (select '', '' + c.name from sys.indexes as ix inner join sys.index_columns as ixc on ixc.object_id = ix.object_id and ixc.index_id = ix.index_id inner join sys.columns as c on c.object_id = ixc.object_id and c.column_id = ixc.column_id where ix.object_id = o.object_id and ix.is_primary_key = 1 FOR XML PATH ('''')), 1, 2, '''' ) + '') WITH (ONLINE = ON)''

							-- when there''s an identity column 
							WHEN EXISTS ( select 1 from sys.columns as c where c.object_id = o.object_id and c.is_identity = 1 ) 
								THEN ''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + 
										'' ADD CONSTRAINT PK_'' + o.name + ''_ID'' + '' PRIMARY KEY CLUSTERED ('' + ( select c.name from sys.columns as c where c.object_id = o.object_id and c.is_identity = 1 ) + '') WITH (ONLINE = ON)''

							-- when there''s a column called id not null
							WHEN EXISTS ( select 1 from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 0 ) 
								THEN ''IF NOT EXISTS ( SELECT TOP 1 '' + ( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 0 ) + '' FROM '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' GROUP BY '' + (( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 0 )) + '' HAVING COUNT(*) > 1 ) '' + ''BEGIN '' +  char(10) + 
										char(9) + ''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + 
										'' ADD CONSTRAINT PK_'' + o.name + ''_ID'' + '' PRIMARY KEY CLUSTERED ('' + ( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 0 ) + '') WITH (ONLINE = ON)'' + char(10) +
									''END '' + char(10) + ''ELSE BEGIN'' + char(10) + 
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' ADD newID INT NOT NULL IDENTITY'''''' + char(10) +
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' ADD CONSTRAINT PK_'' + o.name + ''_newID PRIMARY KEY CLUSTERED (newID) WITH (ONLINE = ON)'''''' + char(10) +
									''END ''

							-- when there''s a column called ID but is nullable
							WHEN EXISTS ( select 1 from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 ) 
								THEN ''IF NOT EXISTS ( SELECT 1 FROM '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' WHERE '' + (( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 )) + '' IS NULL ) '' + char(10) + 
										char(9) + ''AND NOT EXISTS ( SELECT TOP 1 '' + (( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 )) + '' FROM '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' GROUP BY '' + (( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 )) + '' HAVING COUNT(*) > 1 ) '' + ''BEGIN '' +  char(10) + 
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) +
										'' ALTER COLUMN '' + (select c.name + '' '' +  UPPER(t.name) + ISNULL( ''('' + 								
																	CASE 
																		WHEN variable = 1 THEN CONVERT( VARCHAR, CONVERT(INT,(c.max_length * 1.) / (t.length / (t.prec * 1.))) )
																		WHEN t.name = ''float'' THEN CONVERT( VARCHAR, t.prec * 1.)
																	END + '')'', '''' )
																from sys.columns as c inner join sys.systypes as t on t.xusertype = c.user_type_id  where c.object_id = o.object_id  and LOWER(c.name) = ''id'' AND c.is_nullable = 1) + 
											'' NOT NULL '''''' + char(10) + 
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + 
											'' ADD CONSTRAINT PK_'' + o.name + ''_ID'' + '' PRIMARY KEY CLUSTERED ('' + ( select c.name from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' AND c.is_nullable = 1 ) + '') WITH  (ONLINE = ON)'''''' + char(10) + 
									''END'' + char(10) + 
									''ELSE BEGIN'' + char(10) + 
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' ADD newID INT NOT NULL IDENTITY'''''' + char(10) +
										char(9) + ''EXEC sp_executesql N''''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' ADD CONSTRAINT PK_'' + o.name + ''_newID PRIMARY KEY CLUSTERED (newID) WITH (ONLINE = ON)'''''' + char(10) +
									''END'' 
				
							-- When there is no good candidates to be a primary key, create a new column
							WHEN NOT EXISTS ( select 1 from sys.columns as c where c.object_id = o.object_id and LOWER(c.name) = ''id'' ) 
								THEN ''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) +
										'' ADD ID INT NOT NULL IDENTITY'' + char(10) + ''GO'' + char(10) +
									''ALTER TABLE '' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) +
										'' ADD CONSTRAINT PK_'' + o.name + ''_ID'' + '' PRIMARY KEY CLUSTERED (ID) WITH (ONLINE = ON)'' + char(10)
						END	+ char(10) + ''GO'' 
					--, o.object_id
				FROM sys.objects AS o
					INNER JOIN sys.indexes AS ix 
						ON o.object_id = ix.object_id
					INNER JOIN sys.dm_db_partition_stats AS p  
						ON p.object_id = ix.object_id 
							AND p.index_id = ix.index_id
				WHERE 1=1
					AND o.type = ''U'' 
					AND ix.type = 0 -- HEAP
					AND o.is_ms_shipped <> 1 -- To avoid
				ORDER BY 2

		'
		INSERT INTO #result
				(dbname
				, tableName
				, row_count
				, sizeMB
				, hasNonClusteredIndex
				, CREATE_PK_STATEMENT)
		EXEC sp_sqlexec @sqlString

		INSERT INTO #result (CREATE_PK_STATEMENT)
			SELECT '*/'

		SET @countDB = @countDB + 1
	END

	-- Time to retrieve all data collected
	SELECT * FROM #result 
		ORDER BY ID

	-- Drop temp table
	DROP TABLE #result
END			




GO
