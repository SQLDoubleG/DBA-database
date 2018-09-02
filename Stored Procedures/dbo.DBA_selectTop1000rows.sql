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
-- Create date: 20/05/2013
-- Description:	Returns top N rows of a given table
--				and the SELECT statement as message
-- =============================================
CREATE PROCEDURE [dbo].[DBA_selectTop1000rows]
	@tableName			SYSNAME
	, @includeSp_help	BIT = 0
	, @nRows			INT = 1000 
	, @debugging		BIT = 0
AS
BEGIN
	
	SET NOCOUNT ON
	
	-- holds all tables which match the given table
	CREATE TABLE #result(
		ID INT IDENTITY
		, dbname		SYSNAME
		, schemaName	SYSNAME
		, tableName		SYSNAME
		, sqlStatement	NVARCHAR(4000))
	
	-- All online databases
	DECLARE @databases TABLE (
		ID		INT IDENTITY
		,dbname SYSNAME)

	-- Local variables 
	DECLARE @sql				NVARCHAR(4000)
			, @sql2				NVARCHAR(4000)
			, @dbname			SYSNAME
			, @countDB			INT = 1
			, @numDB			INT
			, @countResults		INT = 1
			, @numResults		INT
			
	INSERT INTO @databases 
		SELECT TOP 100 PERCENT name 
			FROM sys.databases 
			WHERE [name] NOT IN ('model') 
				AND state = 0 
			ORDER BY name ASC

	SET @numDB = @@ROWCOUNT

	WHILE @countDB <= @numDB BEGIN
		SET @dbname = (SELECT dbname FROM @databases WHERE ID = @countDB)
	
		SET @sql = N'
			USE ' + QUOTENAME(@dbname) + N'

			DECLARE @sql				NVARCHAR(4000)

			DECLARE @schemas TABLE
				(ID					INT IDENTITY
				, schemaName		SYSNAME
				, schemaDotTable	SYSNAME
				, sqlStatement		VARCHAR(4000) NULL)

			-- Get all schemas the table name belongs to 
			INSERT INTO @schemas (schemaName, schemaDotTable)
			SELECT 	QUOTENAME(CASE WHEN OBJECT_SCHEMA_NAME(OBJECT_ID(@tableName)) IS NOT NULL THEN OBJECT_SCHEMA_NAME(OBJECT_ID(@tableName))
									ELSE SCHEMA_NAME(schema_id)
								END)
					, QUOTENAME(CASE WHEN OBJECT_SCHEMA_NAME(OBJECT_ID(@tableName)) IS NOT NULL THEN OBJECT_SCHEMA_NAME(OBJECT_ID(@tableName))
						ELSE SCHEMA_NAME(schema_id)
					END) + N''.'' +					
						QUOTENAME(
						CASE WHEN CHARINDEX(''.'', @tableName COLLATE DATABASE_DEFAULT) > 0 
							THEN RIGHT(@tableName, LEN(@tableName) - CHARINDEX(''.'', @tableName COLLATE DATABASE_DEFAULT) ) 
							ELSE @tableName 
						END)
				FROM sys.all_objects WHERE name = @tableName -- for sys tables which return null 

			--Generate SQL statements to be printed/executed later
			UPDATE @schemas 
				SET sqlStatement = N''SELECT TOP '' + CONVERT(NVARCHAR, @nRows) + CHAR(10) + REPLICATE(CHAR(9),2) + 
										STUFF( (SELECT REPLICATE(CHAR(9),2) + N'', '' + QUOTENAME(c.name) + char(10)
													FROM sys.all_objects as o 
														INNER JOIN sys.all_columns as c
															ON o.object_id = c.object_id
													WHERE o.name = @tableName
														AND QUOTENAME(SCHEMA_NAME(o.schema_id)) = schemaName
													ORDER BY c.column_id
													FOR XML PATH ('''')), 1,4,'''' ) + CHAR(9) +''FROM '' + QUOTENAME(DB_NAME()) + ''.'' + schemaDotTable + CHAR(10) + N''GO''

			SELECT DB_NAME(), schemaName, schemaDotTable, sqlStatement 
				FROM @schemas 
				WHERE sqlStatement IS NOT NULL

		'
		--PRINT @sql
		INSERT INTO #result
		EXECUTE sp_executesql @sql
				, @params = N'@tableName SYSNAME, @nRows INT, @debugging BIT'
				, @tableName = @tableName
				, @nRows = @nRows
				, @debugging= @debugging

		SET @countDB = @countDB + 1
	END		
		
	-- Get counters for the loop
	SELECT @countResults = MIN(ID)
			, @numResults = MAX(ID)
		FROM #result
	
	IF @numResults > 0 BEGIN 
		-- Go through the sql statements generated
		WHILE @countResults <= @numResults BEGIN
			SELECT @sql		= sqlStatement 
					, @sql2 = N'EXEC ' + CASE WHEN schemaName NOT IN ('[sys]', '[INFORMATION_SCHEMA]') THEN QUOTENAME(r.dbname) + N'.' ELSE N'' END + N'dbo.sp_help ''' + r.tableName + '''' + CHAR(10) + 'GO' + CHAR(10)
				FROM #result as r
				WHERE ID = @countResults
			
			PRINT @sql
			PRINT @sql2
			EXECUTE sp_executesql @sql
			IF @includeSp_help = 1 BEGIN
				EXECUTE sp_executesql @sql2
			END

			SELECT @countResults = MIN(ID)
				FROM #result
				WHERE ID > @countResults
		END
	END 
	ELSE BEGIN
		PRINT 'Impossible to locate object ' + QUOTENAME(@tableName)
	END
		
	-- Drop temp tables
	DROP TABLE #result
END




GO
