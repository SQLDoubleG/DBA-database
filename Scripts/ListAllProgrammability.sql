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
-- Create date: 28/03/2015 
-- Description:	List all programmability for a database 
-- 
-- Log: 
--				19/09/2016	SZO	added "FAST_FORWARD" to "CURSOR FORWARD_ONLY READ_ONLY" 
--				12/01/2017	SZO added functionality to check on object type 
--				13/01/2017	SZO added functionality to check on schema name 
--				19/03/2018	RAG added columns
--									-  raw_definition --> this will help to deploy the DBA database to the different servers
--									-  data_size
--				20/03/2018	RAG Changed the way we replace CREATE for ALTER to allow multiple spaces between CREATE and the object type
--				20/03/2018	RAG Back to the old code since PATINDEX does not have regex support to do something like (?<name>CREATE[ \n\t]{1,}PROC)
--									which will return the right results. 
-- 
-- ============================================= 
DECLARE @dbname			SYSNAME = 'WideWor%' 
		, @schema_name	SYSNAME = NULL 
		, @module_name	SYSNAME = NULL 
		, @object_type  CHAR(2) = NULL 
 
IF @object_type IS NOT NULL AND @object_type NOT IN ('FN', 'IF', 'P', 'TF', 'TR', 'V') 
BEGIN 
	RAISERROR ('Invalid type in @object_type. Please specify one of these options: 		 
		''FN'' (for SQL scalar functions), 	 
		''IF'' (for SQL inline table-valued functions), 	 
		''P'' (for SQL Stored Procedures), 			 
		''TF'' (for SQL table-valued-functions), 
		''TR'' (for SQL triggers), 	 	 
		''V'' (for Views)', 16, 0) WITH NOWAIT 
	GOTO OnError 
END 

DECLARE @sql NVARCHAR(MAX) 

CREATE TABLE #output( 
	database_name		SYSNAME			NOT NULL 
	, object_name		SYSNAME 		NOT NULL
	, schema_name		SYSNAME 		NOT NULL
	, type_desc			NVARCHAR(60) 	NOT NULL
	, definition		NVARCHAR(MAX) 	NOT NULL
	, raw_definition	NVARCHAR(MAX)	NOT NULL
	, data_size			INT				NOT NULL) 

DECLARE dbs CURSOR FORWARD_ONLY READ_ONLY FAST_FORWARD LOCAL
	FOR SELECT name FROM sys.databases WHERE name LIKE ISNULL(@dbname, name); 

OPEN dbs 

FETCH NEXT FROM dbs INTO @dbname 

WHILE @@FETCH_STATUS = 0 BEGIN 

	SET @sql = N'USE ' + QUOTENAME(@dbname)	+ N' 
		DECLARE @module_name SYSNAME = ' + CASE WHEN @module_name IS NULL THEN N'NULL' ELSE N'''' + @module_name + N'''' END + N' 
		DECLARE @schema_name SYSNAME = ' + CASE WHEN @schema_name IS NULL THEN N'NULL' ELSE N'''' + @schema_name + N'''' END + N' 
		DECLARE @object_type char(2) = ' + CASE WHEN @object_type IS NULL THEN N'NULL' ELSE N'''' + @object_type + N'''' END + N' 

		SELECT DB_NAME() AS database_name 
				, o.name AS [object_name] 
				, SCHEMA_NAME(o.schema_id) AS [schema_name] 
				, o.type_desc 
				,  
				N''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + N''GO'' + CHAR(10) +  
				''IF OBJECT_ID ('''''' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) +  '''''') IS NULL EXECUTE sp_executesql N'''''' +  
						CASE  
							WHEN o.type = ''P''		THEN ''CREATE PROCEDURE ''	+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' AS SELECT 1 AS col1''''''  
							WHEN o.type = ''FN''	THEN ''CREATE FUNCTION ''	+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + ''() RETURNS INT AS BEGIN RETURN 0 END'''''' 
							WHEN o.type = ''TF''	THEN ''CREATE FUNCTION ''	+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + ''() RETURNS TABLE AS RETURN (SELECT 1 AS Col1)'''''' 
							WHEN o.type = ''IF''	THEN ''CREATE FUNCTION ''	+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + ''() RETURNS TABLE AS RETURN (SELECT 1 AS Col1)'''''' 
							WHEN o.type = ''V''		THEN ''CREATE VIEW ''		+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) + '' AS SELECT 1 AS col1'''''' 
							WHEN o.type = ''TR''	THEN ''CREATE TRIGGER ''	+ QUOTENAME(SCHEMA_NAME(o.schema_id)) + ''.'' + QUOTENAME(o.name) +  
								'' ON '' + QUOTENAME(OBJECT_SCHEMA_NAME(o.parent_object_id)) + ''.'' + QUOTENAME(OBJECT_NAME(o.parent_object_id)) + 
								CASE WHEN tr.is_instead_of_trigger = 1 THEN '' INSTEAD OF '' ELSE '' AFTER '' END +  
								STUFF( (SELECT '', '' + tre.type_desc FROM sys.trigger_events AS tre WHERE tre.object_id = tr.object_id FOR XML PATH('''')), 1,2,'''') + 
								'' AS SELECT 1 AS col1'''''' 
						END +  
					CHAR(10) + ''GO'' + CHAR(10) +  
						
				N''SET ANSI_NULLS '' +  CASE WHEN uses_ansi_nulls = 1 THEN ''ON'' ELSE ''OFF'' END + CHAR(10) + N''GO'' + CHAR(10) +  
				N''SET QUOTED_IDENTIFIER '' + CASE WHEN uses_quoted_identifier  = 1 THEN ''ON'' ELSE ''OFF'' END + CHAR(10) + N''GO'' + CHAR(10) +  
				REPLACE([definition],  
					CASE  
						WHEN o.type = ''P''						THEN ''CREATE PROC''
						WHEN o.type IN (''FN'',''TF'', ''IF'')	THEN ''CREATE FUNCTION'' 
						WHEN o.type = ''V''						THEN ''CREATE VIEW''  
						WHEN o.type = ''TR''					THEN ''CREATE TRIGGER''  
					END,  
					CASE  
						WHEN o.type = ''P''						THEN ''ALTER PROC''
						WHEN o.type IN (''FN'',''TF'', ''IF'')	THEN ''ALTER FUNCTION'' 
						WHEN o.type = ''V''						THEN ''ALTER VIEW''  
						WHEN o.type = ''TR''					THEN ''ALTER TRIGGER''  
					END) 
				+ N''GO'' AS [definition]
				, [definition] AS raw_definition
				, LEN([definition]) AS data_size 
			FROM sys.sql_modules AS m 
				INNER JOIN sys.objects AS o 
					ON o.object_id = m.object_id 
				LEFT JOIN sys.triggers AS tr 
					ON tr.object_id = o.object_id 
			WHERE o.name LIKE ISNULL(@module_name, o.name) 
				AND SCHEMA_NAME(o.schema_id) LIKE ISNULL(@schema_name, SCHEMA_NAME(o.schema_id)) 
				AND o.[type] = ISNULL(@object_type, o.[type]) 
				AND o.is_ms_shipped = 0' 

	--SELECT @sql
	INSERT INTO #output 
	EXECUTE sp_executesql @sql 

	FETCH NEXT FROM dbs INTO @dbname 
END 

CLOSE dbs; 
DEALLOCATE dbs; 

SELECT database_name
		, object_name
		, schema_name
		, type_desc
		, definition
		, raw_definition
		, data_size  
	FROM #output 
	ORDER BY [database_name], type_desc, schema_name, object_name 

OnError:
GO
