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
-- Create date: 16/02/2021
-- Description:	Retuns or executes the code for adding or modifying tempdb files
--                  according to the number of cores present on the server
--
-- Parameters:
--				@path	        > Where the files will be added / moved		
--              @fileSize_MB	> Size of the DATA files in MB
--              @fileGrowth_MB	> Growth of the DATA files in MB
--              @logSize_MB		> Size of the LOG file in MB
--              @logGrowth_MB	> Growth of the LOG file in MB
--              @execute		> Y or N to excute the commands or just print it
--
-- Limitations:	This script will not validate permissions on the directories
--
-- Log History:	
--				16/02/2021	RAG Created
--
-- =============================================

DECLARE @path					NVARCHAR(512) = 'Z:\tempdb\'
DECLARE @fileSize_MB			SMALLINT = 10240
DECLARE @fileGrowth_MB			SMALLINT = 1024
DECLARE @logSize_MB				SMALLINT = 4096
DECLARE @logGrowth_MB			SMALLINT = 1024
DECLARE @execute				CHAR(1) = 'N'

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- =============================================

DECLARE @SQL					NVARCHAR(4000)
DECLARE @cores_per_numa_node	INT = (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')

IF OBJECT_ID('tempdb..#pathExists') IS NOT NULL DROP TABLE #pathExists

CREATE TABLE #pathExists(
file_exists		BIT
, is_dir		BIT
, parent_exists BIT
);

INSERT #pathExists (file_exists, is_dir, parent_exists)
EXEC xp_fileexist @path;

IF NOT EXISTS (SELECT * FROM #pathExists WHERE is_dir = 1) BEGIN
	RAISERROR ('The specified path does not exist, please provide a valid path', 16, 1, 1)
	RETURN
END;


DECLARE @dbfiles TABLE(
file_id			INT
, file_exists	BIT
, logical_name	SYSNAME
, physical_name NVARCHAR(512)
, size_mb		INT
, growth_mb		INT
)

;WITH cte AS (
	SELECT 1 AS file_id
	UNION ALL
	SELECT file_id + 1
	FROM cte
	WHERE file_id <= @cores_per_numa_node
)

INSERT INTO @dbfiles 
SELECT cte.file_id
		, CASE WHEN mf.file_id IS NOT NULL THEN 1 ELSE 0 END as file_exists
		, ISNULL(mf.name, 'temp' + CONVERT(SYSNAME, cte.file_id -1))
		, @path + ISNULL(RIGHT(mf.physical_name, CHARINDEX('\',REVERSE(mf.physical_name), 1) -1), 'tempdb_mssql_' + CONVERT(SYSNAME, cte.file_id -1) + '.ndf')
		, CASE WHEN cte.file_id <> 2 THEN @fileSize_MB ELSE @logSize_MB END 
		, CASE WHEN cte.file_id <> 2 THEN @fileGrowth_MB ELSE @logGrowth_MB END 
	FROM cte
		LEFT JOIN sys.master_files AS mf
			ON mf.database_id = 2
				AND mf.file_id = cte.file_id


DECLARE c CURSOR LOCAL STATIC FORWARD_ONLY FOR
	SELECT 'ALTER DATABASE [tempdb]' + CASE WHEN file_exists = 1 THEN ' MODIFY' ELSE ' ADD' END + ' FILE' +
				' (NAME = ' + QUOTENAME(logical_name) + 
				', FILENAME = ''' + physical_name + '''' + 
				', SIZE = ' + CONVERT(SYSNAME, size_mb) + 'MB' + 
				', FILEGROWTH = ' + CONVERT(SYSNAME, growth_mb) + 'MB)' AS sqlcmd
	FROM @dbfiles
	ORDER BY file_id
OPEN c
FETCH NEXT FROM c INTO @SQL
WHILE @@FETCH_STATUS = 0 BEGIN
	
	IF @execute = 'Y' BEGIN
		EXECUTE sp_executesql @SQL
	END ELSE BEGIN
		PRINT @SQL
	END
	
	FETCH NEXT FROM c INTO @SQL
END
CLOSE c
DEALLOCATE c

