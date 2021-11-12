SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON; 
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
--				@fileMaxSize_MB	> Max size of the DATA files in MB
--              @fileGrowth_MB	> Growth of the DATA files in MB
--              @logSize_MB		> Size of the LOG file in MB
--              @logGrowth_MB	> Growth of the LOG file in MB
--              @execute		> Y or N to excute the commands or just print it
--
-- Limitations:	This script will not validate permissions on the directories
--
-- Log History:	
--				16/02/2021	RAG Created
--				16/02/2021	RAG Created
--
-- =============================================

DECLARE @path          	nvarchar(512) = 'Z:\tempdb\'
DECLARE @fileSize_MB   	smallint = 2048
DECLARE @fileMaxSize_MB	smallint = 20480
DECLARE @fileGrowth_MB 	smallint = 2048
DECLARE @logSize_MB    	smallint = 4096
DECLARE @logGrowth_MB  	smallint = 1024
DECLARE @execute       	char(1) = 'Y';

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- =============================================

DECLARE @SQL                    nvarchar(4000)
DECLARE @cores_per_numa_node    int;
DECLARE @n_data_files           int;

DROP TABLE IF EXISTS #cmd;

SELECT @n_data_files         = COUNT(*)
	FROM tempdb.sys.database_files AS df
	WHERE type_desc = 'ROWS';

SELECT @cores_per_numa_node = (SELECT t.hyperthread_ratio / COUNT(DISTINCT s.parent_node_id) AS physical_cores_per_numa_node 
									FROM sys.dm_os_schedulers AS s
										CROSS APPLY (SELECT hyperthread_ratio FROM sys.dm_os_sys_info) AS t
									WHERE s.status = N'VISIBLE ONLINE'
									GROUP BY t.hyperthread_ratio);

SET @cores_per_numa_node = (CASE WHEN @cores_per_numa_node < @n_data_files THEN @n_data_files ELSE @cores_per_numa_node END)

-- Adjust the number of files to 8 or less + 1 for the log file
SET @cores_per_numa_node = CASE WHEN @cores_per_numa_node > 8 THEN 8 ELSE @cores_per_numa_node END + 1; -- + log file

;WITH tempdb_files AS(
SELECT 1 AS id
UNION ALL
SELECT tempdb_files.id + 1
    FROM tempdb_files
    WHERE tempdb_files.id < @cores_per_numa_node 
)
-- Primary Data File
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME=[tempdev], ' +
									'FILENAME=''' + @path + 'tempdb.mdf'', ' + 
                                    'SIZE=' + CONVERT(varchar(30),@fileSize_MB) + 'MB, ' + 
                                    'MAXSIZE=' + CONVERT(varchar(30),@fileMaxSize_MB) + 'MB, ' + 
                                    'FILEGROWTH=' + CONVERT(varchar(30),@fileGrowth_MB) + 'MB)' AS AddModifyFile
    INTO #cmd
UNION ALL
-- Log file
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME=[templog], ' +
									'FILENAME=''' + @path + 'templog.ldf'', ' + 
									'SIZE=' + CONVERT(varchar(30),@logSize_MB) + 'MB, ' + 
									'FILEGROWTH=' + CONVERT(varchar(30),@logGrowth_MB) + 'MB)' AS AddFile
UNION ALL
-- Existing secondary data files
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME='+ QUOTENAME(fs.name) +', ' + 
									CASE WHEN fs.name <> 'tempdev_' + CONVERT(varchar(30),f.id-1) 
										THEN 'NEWNAME=''tempdev_' + CONVERT(varchar(30),f.id-1) + ''', ' 
										ELSE ''
									END +
                                    'FILENAME=''' + @path + 'tempdev_' + CONVERT(varchar(30),f.id-1) + '.ndf'', ' + 
                                    'SIZE=' + CONVERT(varchar(30),@fileSize_MB) + 'MB, ' + 
                                    'MAXSIZE=' + CONVERT(varchar(30),@fileMaxSize_MB) + 'MB, ' + 
                                    'FILEGROWTH=' + CONVERT(varchar(30),@fileGrowth_MB) + 'MB)' AS AddFile     
    FROM tempdb_files AS f
	INNER JOIN tempdb.sys.database_files AS fs
		ON f.id = fs.file_id
    WHERE f.id <= @cores_per_numa_node
	AND f.id > 2
UNION ALL
-- Files to be added
SELECT 'ALTER DATABASE tempdb ADD FILE(NAME=''tempdev_' + CONVERT(varchar(30),f.id-1) + ''', ' + 
                                        'FILENAME=''' + @path + 'tempdev_' + CONVERT(varchar(30),f.id-1) + '.ndf'', ' + 
                                        'SIZE=' + CONVERT(varchar(30),@fileSize_MB) + 'MB, ' + 
										'MAXSIZE=' + CONVERT(varchar(30),@fileMaxSize_MB) + 'MB, ' + 
                                        'FILEGROWTH=' + CONVERT(varchar(30),@fileGrowth_MB) + 'MB)' AS AddFile     
    FROM tempdb_files AS f
	LEFT JOIN tempdb.sys.database_files AS fs
		ON f.id = fs.file_id
    WHERE f.id <= @cores_per_numa_node 
		AND fs.file_id IS NULL
	
-- Now remove if existing files are as desired
EXCEPT 
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME=['+ name + '], ' +
									'FILENAME=''' + physical_name + ''', ' + 
                                    'SIZE=' + CONVERT(varchar(30),size / 128) + 'MB, ' + 
                                    'MAXSIZE=' + CONVERT(varchar(30),@fileMaxSize_MB) + 'MB, ' + 
                                    'FILEGROWTH=' + CONVERT(varchar(30),growth / 128) + 'MB)' AS AddModifyFile
	FROM tempdb.sys.database_files
	WHERE file_id = 1
EXCEPT 
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME=['+ name + '], ' +
									'FILENAME=''' + physical_name + ''', ' + 
                                    'SIZE=' + CONVERT(varchar(30),size / 128) + 'MB, ' + 
                                    'FILEGROWTH=' + CONVERT(varchar(30),growth / 128) + 'MB)' AS AddModifyFile
	FROM tempdb.sys.database_files
	WHERE file_id = 2
EXCEPT
SELECT 'ALTER DATABASE tempdb MODIFY FILE(NAME='+ QUOTENAME(fs.name) +', ' + 
									CASE WHEN fs.name <> 'tempdev_' + CONVERT(varchar(30),f.id-1) 
										THEN 'NEWNAME=''tempdev_' + CONVERT(varchar(30),f.id-1) + ''', ' 
										ELSE ''
									END +
                                    'FILENAME=''' + @path + 'tempdev_' + CONVERT(varchar(30),f.id-1) + '.ndf'', ' + 
                                    'SIZE=' + CONVERT(varchar(30), size / 128 ) + 'MB, ' + 
                                    'MAXSIZE=' + CONVERT(varchar(30),@fileMaxSize_MB) + 'MB, ' + 
                                    'FILEGROWTH=' + CONVERT(varchar(30), growth / 128) + 'MB)' AS AddFile     
    FROM tempdb_files AS f
	INNER JOIN tempdb.sys.database_files AS fs
		ON f.id = fs.file_id
    WHERE f.id <= @cores_per_numa_node
	AND fs.name = 'tempdev_' + CONVERT(varchar(30),f.id-1)
	AND fs.physical_name = @path + 'tempdev_' + CONVERT(varchar(30),f.id-1) + '.ndf'
	AND f.id > 2;

DECLARE cr CURSOR LOCAL FAST_FORWARD FORWARD_ONLY READ_ONLY FOR
    SELECT AddModifyFile FROM #cmd;
OPEN cr; 
FETCH NEXT FROM cr INTO @sql;
WHILE @@FETCH_STATUS = 0 BEGIN
    IF @execute = 'Y' BEGIN
        EXECUTE sys.sp_executesql @stmt = @sql;
    END; 
    ELSE BEGIN
        PRINT @sql;
    END;
    FETCH NEXT FROM cr INTO @sql;
END;
CLOSE cr;
DEALLOCATE cr;