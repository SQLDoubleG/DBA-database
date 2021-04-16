SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON 
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
-- Create date: 20/05/2013 
-- Description:	Returns a list of objects which contains the  
--				given pattern and their definition 
--
-- Parameters:
--				- @pattern			>> Pattern to search for, it will be used as %pattern%
--				- @dbname			>> database to search into, allows wildcards. Use NULL for ALL Databases in the server
--				- @EngineEdition	>> used to force the current database in Azure SQL DB
-- 
-- Log History:	18/08/2013 - RAG - Included functionality to look for the pattern in job steps 
--				19/08/2013 - RAG - Changed Global temp table for a local temp table to avoid concurrency problems 
--				28/11/2013 - RAG - Included database name for job steps instead of SQL Agent 
--				30/05/2014 - RAG - Included GO at the end of any SQL module  
--				04/12/2014 - RAG - Included search into sysarticles if exists 
--				25/04/2016 - SZO - Included ability to specify database to search 
--				31/10/2016 - SZO - Included ability to check definition of check constraints 
--				01/11/2016 - SZO - Included ability to check definition of default constraints 
--				16/11/2016 - SZO - Changes script to group check and default constraints together 
--				30/09/2018 - RAG - Added specific query for foreign keys that will desplay 
--										the referenced column and referential actions
--				14/10/2018 - RAG - Added TRY CATCH block to allow databases to be non accessible like secondary non-readble 
--				14/01/2021 - RAG - Added parameter @EngineEdition
--				20/01/2021 - RAG - Added table name to Default constraint objectName
--				15/04/2021 - RAG - Added user defined Table types
--
-- ============================================= 
DECLARE @pattern			SYSNAME = 'pattern'
		, @dbname			SYSNAME = NULL
		, @EngineEdition	INT		= CONVERT(INT, SERVERPROPERTY('EngineEdition'))

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

SET @pattern = '%' + @pattern + '%'

IF OBJECT_ID('tempdb..#result')	IS NOT NULL DROP TABLE #result 

CREATE TABLE #result( 
	databaseName		SYSNAME 
	, objectName		SYSNAME 
	, objectTypeDesc	SYSNAME 
	, objectDefinition	NVARCHAR(MAX) 
) 

DECLARE @databases TABLE ( 
	ID		INT IDENTITY 
	,dbname SYSNAME) 

-- Local variables  
DECLARE @sqlstring			NVARCHAR(MAX) 
		, @countDB			INT = 1 
		, @numDB			INT 
		, @countResults		INT = 1 
		, @numResults		INT 

DECLARE @errMsg				NVARCHAR(500)

-- All online databases 
INSERT INTO @databases  
	SELECT TOP 100 PERCENT name  
		FROM sys.databases  
		WHERE [name] NOT IN ('model', 'tempdb')  
			AND state = 0  
			AND [name] LIKE ISNULL(@dbname, [name])  
		ORDER BY name ASC 

SET @numDB = @@ROWCOUNT 

WHILE @countDB <= @numDB BEGIN 
	SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDB) 
	
	SET @sqlString = CASE WHEN @EngineEdition <> 5 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
		+ N'

		INSERT INTO #result ( databaseName, objectName, objectTypeDesc, objectDefinition) 
			SELECT DB_NAME() 
					, QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) + ''.'' + QUOTENAME(o.name) 
					, o.type_desc 
					, ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) + RTRIM(LTRIM(m.[definition])) + CHAR(10) + ''GO'' 
				FROM sys.objects as o 
					LEFT JOIN sys.sql_modules as m 
						ON m.object_id = o.object_id 
				WHERE ( o.name LIKE @pattern OR m.definition LIKE @pattern ) 
					-- handled in the final union, creates duplicate results. 
					AND o.type_desc NOT IN (''CHECK_CONSTRAINT'', ''DEFAULT_CONSTRAINT'', ''FOREIGN_KEY_CONSTRAINT'') 
					AND o.is_ms_shipped = 0 
			UNION ALL
			SELECT DB_NAME() 
					, QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) + ''.'' + QUOTENAME(o.name) + ''.'' + QUOTENAME(c.name) 
					, o.type_desc + ''_COLUMN'' 
					, t.name + ISNULL((CASE WHEN t.xtype = t.xusertype  
											THEN ''('' + CONVERT( VARCHAR, CONVERT(INT,(c.max_length * 1.) / (t.length / (NULLIF(t.prec, 0) * 1.))) ) + '')'' 
											ELSE '''' 
										END), '''') 
				FROM sys.columns as c 
					INNER JOIN sys.objects AS o 
						ON o.object_id = c.object_id 
					INNER JOIN systypes as t 
						ON t.xusertype = c.user_type_id 
				WHERE c.name LIKE @pattern 
					AND is_ms_shipped = 0 
			UNION ALL 
			SELECT DB_NAME() 
					, QUOTENAME(OBJECT_SCHEMA_NAME(o.[parent_object_id])) + ''.''
						+ QUOTENAME(OBJECT_NAME(o.[parent_object_id])) + ''.''
						+ QUOTENAME(o.name) 
					, o.type_desc 
					, RTRIM(LTRIM(ISNULL(dc.[definition], cc.[definition]))) 
				FROM sys.objects AS o 
					LEFT JOIN sys.default_constraints AS dc 
						ON o.[object_id] = dc.[object_id] 
					LEFT JOIN sys.check_constraints AS cc 
						ON o.[object_id] = cc.[object_id] 
				WHERE (dc.[definition] LIKE @pattern OR cc.[definition] LIKE @pattern 
						OR dc.name LIKE @pattern OR cc.name LIKE @pattern) 
					AND o.is_ms_shipped = 0 
			UNION ALL 
			SELECT DB_NAME() 
					, QUOTENAME(OBJECT_SCHEMA_NAME(o.[object_id])) + ''.'' + QUOTENAME(o.name) 
					, o.type_desc 
					, ''REFERENCES '' + QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) + ''.'' 
							+ QUOTENAME(OBJECT_NAME(fk.referenced_object_id)) + ''.''  
							+ QUOTENAME(COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id))
							+ '' ON DELETE '' + fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT
							+ '', ON UPDATE '' + fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT
				FROM sys.objects AS o 
					INNER JOIN sys.foreign_keys AS fk
						ON fk.[object_id] = o.[object_id] 
					LEFT JOIN sys.foreign_key_columns AS fkc
						ON fkc.constraint_object_id = fk.object_id

				WHERE o.name LIKE @pattern 
					AND o.is_ms_shipped = 0 
            UNION ALL
            SELECT DB_NAME() 
					, QUOTENAME(SCHEMA_NAME(tt.[schema_id])) + ''.'' + QUOTENAME(tt.[name]) 
					, o.type_desc 
					, ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) +
						''CREATE TYPE '' + QUOTENAME(SCHEMA_NAME(tt.[schema_id])) + ''.'' + QUOTENAME(tt.[name]) + '' AS TABLE ('' + CHAR(10) +
						STUFF(
						(SELECT '', '' + ac.name + '' '' + ty.name + '' ('' + 
							
								CAST(CASE WHEN ty.name IN (N''nchar'', N''nvarchar'') AND ac.max_length <> -1 THEN ac.max_length/2 
										ELSE ac.max_length 
									END AS VARCHAR(30)) + '')'' +
								CASE WHEN ac.is_nullable = 0 THEN '' NOT'' ELSE '''' END + '' NULL'' + CHAR(10)

							FROM sys.all_columns AS ac
							INNER JOIN sys.types AS ty
								ON ty.user_type_id = ac.user_type_id

							WHERE ac.object_id = o.object_id
							FOR XML PATH('''')), 1,2,'''') 
						+ '')'' AS [definition]
				FROM sys.objects AS o 
					INNER JOIN sys.table_types AS tt
						ON tt.type_table_object_id = o.[object_id] 
				WHERE o.name LIKE @pattern 

		IF OBJECT_ID(''sysarticles'') IS NOT NULL BEGIN  
			INSERT INTO #result ( databaseName, objectName, objectTypeDesc, objectDefinition) 
				SELECT DB_NAME() 
						, name 
						, ''REPLICATION ARTICLE'' 
						, '''' 
					FROM dbo.sysarticles AS a							 
					WHERE a.name LIKE @pattern  
						OR a.del_cmd LIKE @pattern  
						OR a.ins_cmd LIKE @pattern  
						OR a.upd_cmd LIKE @pattern  
		END  
	' 
	--SELECT @sqlstring
	BEGIN TRY
		EXECUTE sp_executesql @stmt = @sqlstring, @params = N'@pattern SYSNAME', @pattern = @pattern
	END TRY
	BEGIN CATCH
		SET @errMsg = 'There was an error accessing ' + QUOTENAME(@dbname) 
		PRINT @errMsg
	END CATCH

	SET @countDB = @countDB + 1 
END		 

IF @EngineEdition <> 5 BEGIN
	SET @sqlstring = N'SELECT js.database_name 
			, j.name + N''. Step '' + CONVERT(NVARCHAR, js.step_id) + N'' ('' + js.step_name + N'')'' + CASE WHEN j.enabled = 0 THEN N'' (Disabled)'' ELSE N'''' END 
			, ''SQL AGENT JOB'' 
			, js.command 
		FROM msdb.dbo.sysjobs AS j 
			INNER JOIN msdb.dbo.sysjobsteps AS js 
				ON js.job_id = j.job_id 
		WHERE js.command LIKE @pattern'

	INSERT INTO #result ( databaseName, objectName, objectTypeDesc, objectDefinition) 
	EXECUTE sp_executesql @stmt = @sqlstring, @params = N'@pattern SYSNAME', @pattern = @pattern
END
	

SELECT databaseName 
		, objectName 
		, objectTypeDesc 
		, objectDefinition 
	FROM #result  
	ORDER BY 1,3,2 

GO