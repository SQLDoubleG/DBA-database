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
-- =============================================
DECLARE 
	@dbname				SYSNAME 

	SET NOCOUNT ON

	DECLARE @dbs TABLE (
		ID			INT IDENTITY(1,1)
		, dbname	SYSNAME)

	DECLARE @dbfiles TABLE (
		[db_name]		SYSNAME
		, type_desc		SYSNAME
		, sizeMB		DECIMAL(10,2)
	)

	DECLARE @db				SYSNAME = NULL
			, @countDBs		INT = 1
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

		SET @db			= ( SELECT dbname FROM @dbs WHERE ID = @countDBs )
		
		IF DATABASEPROPERTYEX(@db,'Status') = 'ONLINE' BEGIN
		
			SET @sqlstring	= N'
		
			USE ' + QUOTENAME(@db) + N'
		
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
		
			SELECT ''' + @db + N''', df.type_desc, (size*8.)/1024. 
				FROM sys.master_files AS df
				WHERE database_id = DB_ID(''' + @db + N''')
			UNION ALL 
			SELECT ''' + @db + N''', ''ALLOC'', NULL
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
            , CONVERT(DECIMAL(10,2), ([ROWS] + [LOG] + ISNULL([FILESTREAM], 0) + ISNULL([FULLTEXT], 0)) / 1024.) AS TotalSizeGB
        FROM ( 
            SELECT [db_name], type_desc, sizeMB
                FROM @dbfiles 
        ) AS t
        PIVOT(
            SUM(sizeMB)
            FOR type_desc IN ([ROWS],[LOG],[FILESTREAM],[FULLTEXT],[ALLOC])
        ) AS p
    )
    SELECT  [db_name] 
			, [DataSizeMB]
			, [FreeMB]
			, LogSizeMB
			, FilestreamSizeMB
			, FulltextSizeMB
			, TotalSizeMB
			, TotalSizeGB
		FROM all_dbs
GO
