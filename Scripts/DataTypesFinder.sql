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
-- Date:		06/01/2014
-- Description: Finds within a given database or all databases columns using the given data types 
--				The script returns one recordset
--					- db Name
--					- table Name
--					- column Name
--					- Current Data Type
--					- Current Max Lenght
--					- Current Nullability
--					- ALTER TABLE statement
--					- UPDATE statement
--
-- Notes:
--				This SP uses the future deprecated sys.systypes view to calculate columns max_lenght
--
-- Paramters:	
--				- @dbname
--				- @dataTypes, comma separated data type names
--				- @onlyDeprecated, will look for data types text, ntext and image. Will overwrite the @dataTypes parameter
--
-- Change Log:	
--				20/01/2021	RAG	- Added column definition to display Default Constraint definition if applies
--								- Removed ID column from temp table and Changed ORDER BY to db, schema, table
-- =============================================
DECLARE @dbname				SYSNAME			= NULL
        , @dataTypes		NVARCHAR(1000)	= NULL
        , @onlyDeprecated	BIT				= 1

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

IF OBJECT_ID('tempdb..#results') 		IS NOT NULL DROP TABLE #results

CREATE TABLE #results
	( dbname			SYSNAME NULL
	, schemaName		SYSNAME NULL
	, tableName			SYSNAME NULL
	, columnName		SYSNAME NULL
	, dataType			SYSNAME NULL
	, max_length		INT NULL
	, is_nullable		BIT NULL
	, is_computed		BIT NULL
	, definition		NVARCHAR(MAX) NULL)

DECLARE @databases	TABLE 
	(ID			INT IDENTITY(1,1)
	, dbname	SYSNAME)

IF @onlyDeprecated = 1 AND @dataTypes IS NULL BEGIN
	SET @dataTypes = 'text,ntext,image'
END

DECLARE @numDB		INT
		, @countDB		INT = 1
		, @sqlString	NVARCHAR(MAX)

INSERT @databases (dbname)
	SELECT TOP 100 PERCENT
			name 
		FROM sys.databases d 
		WHERE 1=1
			AND d.name LIKE ISNULL(@dbname, d.name)
			AND d.database_id > 4
			AND d.name NOT LIKE 'ReportServer%'
			AND state = 0 -- Online
		ORDER BY name

SET @numDB = @@ROWCOUNT;

WHILE @countDB <= @numDB BEGIN
	SET @dbname = (SELECT dbname from @databases WHERE ID = @countDB)

	SET @sqlString = N'
		
		USE ' + QUOTENAME(@dbname) + N'	
			
		DECLARE @dbname		SYSNAME		= QUOTENAME(DB_NAME())

		DECLARE @dataTypesTable TABLE (dataType SYSNAME)

		DECLARE @commaPos	INT 

		-- Parse the string of data types and load the table
		WHILE LEN(@dataTypes) > 0 BEGIN

			SET @commaPos = ISNULL( (NULLIF( (CHARINDEX('','', @dataTypes COLLATE DATABASE_DEFAULT, 0)), 0)), LEN(@dataTypes) + 1)

			INSERT INTO @dataTypesTable
				SELECT LTRIM(RTRIM(SUBSTRING( @dataTypes, 0, @commaPos)))
	
			SET @dataTypes = SUBSTRING(@dataTypes, @commaPos + 1, LEN(@dataTypes))

		END

		INSERT INTO #results
				(dbname
				, schemaName
				, tableName
				, columnName
				, dataType
				, max_length
				, is_nullable
				, is_computed
				, definition)
		SELECT	@dbname
				, SCHEMA_NAME(t.schema_id) AS schemaName
				, t.name as tableName
				, c.name as columnName
				, ty.name as dataType
				, CASE WHEN c.max_length = -1 THEN c.max_length ELSE c.max_length * (sty.prec * 1. / sty.length) END
				, c.is_nullable
				, c.is_computed
				, ISNULL(df.definition, '''') AS definition				
			FROM sys.tables as t
				INNER JOIN sys.all_columns AS c
					on c.object_id = t.object_id
				INNER JOIN sys.all_objects AS o
					ON c.object_id = o.object_id
				INNER JOIN sys.types AS ty
					ON c.system_type_id = ty.system_type_id
				INNER JOIN sys.systypes as sty
					ON sty.xusertype = ty.user_type_id
				LEFT JOIN sys.default_constraints AS df
					ON df.parent_object_id = c.object_id
						AND df.parent_column_id = c.column_id
			WHERE ty.name IN (SELECT dataType FROM @dataTypesTable)
				AND t.is_ms_shipped <> 1'
		
	EXEC sp_executesql @stmt = @sqlString, @params = N'@dataTypes NVARCHAR(1000)', @dataTypes = @dataTypes

	SET @countDB = @countDB + 1
END

-- Time to retrieve all data collected
SELECT dbname
		, schemaName
		, tableName
		, columnName
		, UPPER(dataType) AS dataType
		, CASE WHEN max_length = -1 THEN '(MAX)' ELSE CONVERT(VARCHAR, max_length) END AS max_length
		, CASE WHEN is_nullable = 1 THEN 'Yes' ELSE 'No' END AS is_nullable
		, CASE WHEN is_computed = 1 THEN 'Yes' ELSE 'No' END AS is_computed
		, definition
	FROM #results 
	ORDER BY dbname
		, schemaName
		, tableName

GO
