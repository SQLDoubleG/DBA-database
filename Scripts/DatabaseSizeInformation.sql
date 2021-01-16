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
-- Create date: 18/10/2013
-- Description:	Returns database files size (ROWS, LOG, FILESTREAM and FULLTEXT)
--				for a given database or all if not specified
--
-- Parameters:
--				@dbname
--
-- Log History:	2014-01-31 RAG - Changed the totals recodset to use PIVOT and display one row per database
--				2014-10-17 RAG - Added functionality to display info for FILESTREAM and FULLTEXT
--				2018-03-26 RAG - Added system databases
--				2018-09-14 RAG - Changes:
--									- Removed all information related to files and filegroups as that is not diplayed anymore
--									- Added FreeMB information to [DataSizeMB] column, calculation based on allocation units
--				2019-03-20 RAG - Added support for not ONLINE databases by looking at sys.master_files instead
--				2020-04-08 RAG - Added total size for each of the columns
--				14/01/2021 RAG - Added parameter @EngineEdition
--
-- =============================================
DECLARE @dbname				SYSNAME 
		, @EngineEdition	INT		= CONVERT(INT, SERVERPROPERTY('EngineEdition'))

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

DECLARE @dbs TABLE (
	ID			INT IDENTITY(1,1)
	, dbname	SYSNAME)

DECLARE @dbfiles TABLE (
	[db_name]		SYSNAME
	, type_desc		SYSNAME
	, sizeMB		DECIMAL(10,2)
)

DECLARE @countDBs		INT = 1
		, @numDBs		INT
		, @sqlstring	NVARCHAR(2000)

INSERT INTO @dbs (dbname)
	SELECT name 
		FROM sys.databases 
		WHERE name LIKE ISNULL(@dbname, name)
		ORDER BY name

SET @numDBs = @@ROWCOUNT
 
-- Unfortunately sys.master_files returns size 0 for filestream containes, hence the loop.
WHILE @countDBs <= @numDBs BEGIN

	SET @dbname	= ( SELECT dbname FROM @dbs WHERE ID = @countDBs )
		
	IF DATABASEPROPERTYEX(@dbname,'Status') = 'ONLINE' BEGIN
		
	SET @sqlstring		= CASE WHEN @EngineEdition <> 5 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
			+ N'
		SELECT DB_NAME(), df.type_desc, (size*8.)/1024. 
			FROM sys.database_files AS df
		UNION ALL 
		SELECT DB_NAME(), ''ALLOC'', CONVERT(DECIMAL(10,2), SUM(total_pages)	* 8 / 1024.) 
			FROM sys.allocation_units AS au
		'
	END 
	ELSE BEGIN
	SET @sqlstring	= N'		
		USE master
		
		SELECT ''' + @dbname + N''', df.type_desc, (size*8.)/1024. 
			FROM sys.master_files AS df
			WHERE database_id = DB_ID(''' + @dbname + N''')
		UNION ALL 
		SELECT ''' + @dbname + N''', ''ALLOC'', NULL
		'
	END

	PRINT @sqlstring
	INSERT INTO @dbfiles ([db_name], type_desc, sizeMB)
		EXEC sp_executesql @sqlstring

	SET @countDBs = @countDBs + 1
END

;WITH all_dbs AS(
    SELECT [db_name] 
        , [ROWS] AS DataSizeMB
        , [LOG] AS LogSizeMB
		, [ROWS] - [ALLOC] AS FreeMB
        , ISNULL([FILESTREAM], 0) AS FilestreamSizeMB
        , ISNULL([FULLTEXT], 0) AS FulltextSizeMB
        , [ROWS] + [LOG] + ISNULL([FILESTREAM], 0) + ISNULL([FULLTEXT], 0) AS TotalSizeMB

    FROM ( 
        SELECT [db_name], type_desc, sizeMB
            FROM @dbfiles 
    ) AS t
    PIVOT(
        SUM(sizeMB)
        FOR type_desc IN ([ROWS],[LOG],[FILESTREAM],[FULLTEXT],[ALLOC])
    ) AS p
)
SELECT  ISNULL([db_name], '***Total***') AS [db_name]
		/*
		, SUM([DataSizeMB]) AS [DataSizeMB]
		, SUM([DataSizeMB]-[FreeMB]) AS [UsedMB]
		, SUM([FreeMB]) AS [FreeMB]
		, SUM(LogSizeMB) AS LogSizeMB
		, SUM(FilestreamSizeMB) AS FilestreamSizeMB
		, SUM(FulltextSizeMB) AS FulltextSizeMB
		, SUM(TotalSizeMB) AS TotalSizeMB
		--*/
		--/*
		, CONVERT(DECIMAL(10,2), SUM([DataSizeMB])/1024.) AS [DataSizeGB]
		, CONVERT(DECIMAL(10,2), SUM(([DataSizeMB]-[FreeMB]))/1024.) AS [UsedGB]
		, CONVERT(DECIMAL(10,2), SUM([FreeMB])/1024.) AS [FreeGB]
		, CONVERT(DECIMAL(10,2), SUM(LogSizeMB)/1024.) AS LogSizeGB
		, CONVERT(DECIMAL(10,2), SUM(FilestreamSizeMB)/1024.) AS FilestreamSizeGB
		, CONVERT(DECIMAL(10,2), SUM(FulltextSizeMB)/1024.) AS FulltextSizeGB
		, CONVERT(DECIMAL(10,2), SUM(TotalSizeMB)/1024.) AS TotalSizeGB
		--*/
	FROM all_dbs
	GROUP BY [db_name] 
	WITH ROLLUP
	ORDER BY CASE WHEN [db_name] <> '***Total***' THEN 1 ELSE 2 END ASC
GO
