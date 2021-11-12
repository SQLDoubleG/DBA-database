SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON
GO
--=============================================
-- Copyright (C) 2021 Raul Gonzalez, @SQLDoubleG
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
-- Create date: 17/05/2021
-- Description:	Returns duplicates indexes for a database, schema or table specified.
--
-- Assupmtions:	
--
-- Change Log:	17/05/2021 RAG 	- Created
--				
-- =============================================
DECLARE @dbname				SYSNAME		= 'WideWorldImporters'
		, @schemaName		SYSNAME		= NULL
		, @tableName		SYSNAME		= NULL
		, @EngineEdition	INT			= CONVERT(INT, SERVERPROPERTY('EngineEdition'))

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

IF OBJECT_ID('tempdb..#result')		IS NOT NULL DROP TABLE #result
IF OBJECT_ID('tempdb..#databases')	IS NOT NULL DROP TABLE #databases

CREATE TABLE #result(
	database_id INT
	, object_id INT
	, ix_id INT
	, ix_name SYSNAME
	, ix_key_columns NVARCHAR(MAX)
	, ix_included_columns NVARCHAR(MAX)
)

CREATE TABLE #databases 
	( ID			INT IDENTITY
	, dbname		SYSNAME)
	
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
	SET @sqlString = 
	'USE [?]

SELECT DB_ID() AS database_ID
		, ix.object_id
		, ix.index_id
		, ix.name
		, STUFF((SELECT '','' + c.name 
					FROM sys.index_columns AS ixc
					INNER JOIN sys.columns AS c
						ON c.object_id = ixc.object_id
							AND c.column_id = ixc.column_id
					WHERE ixc.object_id = ix.object_id
						AND ixc.index_id = ix.index_id
						AND ixc.is_included_column = 0
					ORDER BY ixc.key_ordinal
					FOR XML PATH('''')),1,1,'''') AS index_key
		, STUFF((SELECT '','' + c.name 
					FROM sys.index_columns AS ixc
					INNER JOIN sys.columns AS c
						ON c.object_id = ixc.object_id
							AND c.column_id = ixc.column_id
					WHERE ixc.object_id = ix.object_id
						AND ixc.index_id = ix.index_id
						AND ixc.is_included_column = 1
					ORDER BY ixc.key_ordinal
					FOR XML PATH('''')),1,1,'''') AS included_columns
FROM sys.indexes AS ix
WHERE ix.index_id > 0 /* ignore heaps */'

	SET @sqlString = REPLACE(@sqlString, '?', @dbname)
	INSERT INTO #result
		EXEC sp_executesql @sqlString
				, N'@tableName SYSNAME, @schemaName SYSNAME'
				, @tableName			= @tableName
				, @schemaName			= @schemaName

	SET @countDB = @countDB + 1
END

SELECT DB_NAME(database_id) AS [database_name]
		, OBJECT_SCHEMA_NAME(object_id, database_id) + '.' + OBJECT_NAME(object_id, database_id) AS object_name
		, ix_key_columns
		, ISNULL(ix_included_columns, '') AS ix_included_columns
		, COUNT(*) ix_count
	FROM #result
	WHERE OBJECTPROPERTY(object_id, 'IsMsShipped') = 0
	GROUP BY database_id
		, object_id
		, ix_key_columns
		, ix_included_columns
	HAVING COUNT(*) > 1
	ORDER BY [database_name]
		, object_name
		, ix_key_columns
		, ix_included_columns
