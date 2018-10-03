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
-- Description:	Returns database files size (ROWS, LOG) and fullness information
--				for a given database or all if not specified
--
-- Remarks:
--				This sp is used by [dbo].[DBA_auditGetDatabaseInformation], so any change here should be reflected there too
--				FILEPROPERTY Returns NULL for files that are not in the current database, therefore should be kept within the loop
--
-- Parameters:
--				@dbname
--
-- Log History:	
--				02/05/2014 RAG - Added volume statistics
--				28/07/2014 RAG - Added functionality to display information for offline database when @dbname is provided
--				08/09/2014 RAG - Added parameter @fileType to filter between different file types (ROWS, LOG, FILESTREAM, FULLTEXT)
--				07/04/2015 RAG - Added column [is_FG_readonly] to display if the Filegroup is READ_ONLY or not
--				13/04/2015 RAG - Changed the way of getting volume stats, only 1 file per drive
--				09/06/2015 RAG - Get file info from sys.master_files to cover all databases, not only ONLINE. Then UPDATE per ONLINE database
--				23/11/2015 RAG - Use TRY...CATCH as AG database replicas are online but maybe not accessible (readable). In that case the process does not stop
--				16/06/2015 RAG - Added column [log_reuse_wait_desc]
--				30/09/2018 RAG Created new Dependencies section
--								- Added dependant function as tempdb object 
--								- Added column [ModifyGrowth] to change auto growth to a fixed value calculated on the current size
--									Current Size > 10000 THEN '4000'  
--									Current Size > 4000 THEN '1000'
--									Current Size > 1000 THEN '500'
--									Other '100'

-- =============================================
-- =============================================
-- Dependencies:This Section will create on tempdb any dependancy
-- =============================================
USE tempdb
GO
CREATE FUNCTION [dbo].[getDriveFromFullPath](
	@path NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	DECLARE @slashPos	INT		= CASE 
									WHEN CHARINDEX( ':', @path ) > 0 THEN CHARINDEX( ':', @path ) 
									WHEN CHARINDEX( '\', @path ) > 0 THEN CHARINDEX( '\', @path ) 
									ELSE NULL 
								END

	RETURN ( CASE WHEN @slashPos IS NULL THEN '\' ELSE LEFT( @path, @slashPos ) END )

END
GO
CREATE FUNCTION [dbo].[getFileNameFromPath](
	@path NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	DECLARE @slashPos	INT		= CASE WHEN CHARINDEX( '\', REVERSE(@path) ) > 0 THEN CHARINDEX( '\', REVERSE(@path) ) -1 ELSE LEN(@path) END
	RETURN RIGHT( @path, @slashPos ) 
END
GO
-- =============================================
-- END of Dependencies
-- =============================================
DECLARE	@dbname		SYSNAME = NULL
		, @fileType	SYSNAME = NULL

SET NOCOUNT ON

IF OBJECT_ID('tempdb..#dbs')			IS NOT NULL DROP TABLE #dbs

IF OBJECT_ID('tempdb..#filesUsage')		IS NOT NULL DROP TABLE #filesUsage

IF OBJECT_ID('tempdb..#volume_stats')	IS NOT NULL DROP TABLE #volume_stats

-- Databases we will loop through
CREATE TABLE #dbs (
	ID					INT IDENTITY(1,1)
	, database_id		INT
	, database_name		SYSNAME)

-- To hold the results of files usage
CREATE TABLE #filesUsage (
	database_id				INT
	, [file_id]				INT
	, [logical_name]		SYSNAME
	, [data_space_id]		INT
	, [type_desc]			SYSNAME
	, [filegroup]			SYSNAME		NULL
	, [is_FG_readonly]		VARCHAR(3)	NULL
	, [max_size]			INT
	, [growth]				INT
	, [is_percent_growth]	BIT
	, [physical_name]		NVARCHAR(512)
	, [size]				BIGINT
	, [spaceUsed]			BIGINT		NULL)

DECLARE @db				SYSNAME = NULL
		, @countDBs		INT = 1
		, @numDBs		INT
		, @sqlstring	NVARCHAR(4000)

IF ISNULL(@fileType, '') NOT IN ('ROWS', 'LOG', 'FILESTREAM', 'FULLTEXT', '') BEGIN
	RAISERROR ('The parameter @fileType accepts only one of the following values: ROWS, LOG, FILESTREAM, FULLTEXT or NULL', 16, 0 ,0)
	GOTO OnError
END

-- Get volume statistics
-- Get one pair database-file per Drive
;WITH cte AS(
	SELECT tempdb.dbo.getDriveFromFullPath(physical_name) AS Drive
			, MIN(database_id) AS database_id
			, (SELECT MIN(file_id) AS file_id
					FROM master.sys.master_files 
					WHERE database_id = MIN(mf.database_id) 
						AND tempdb.dbo.getDriveFromFullPath(physical_name) = tempdb.dbo.getDriveFromFullPath(mf.physical_name)) AS file_id
		FROM master.sys.master_files AS mf
		GROUP BY tempdb.dbo.getDriveFromFullPath(physical_name)
)

SELECT SERVERPROPERTY('MachineName') AS ServerName
		, vs.volume_mount_point AS Drive
		, vs.logical_volume_name AS VolName
		, vs.file_system_type AS FileSystem
		, vs.total_bytes / 1024 / 1024 AS SizeMB
		, vs.available_bytes / 1024 / 1024 AS FreeMB
	INTO #volume_stats
	FROM cte 
		CROSS APPLY master.sys.dm_os_volume_stats (cte.database_id, file_id) AS vs

-- Get files info from sys.master_files to get also from databases not ONLINE
INSERT INTO #filesUsage (database_id
						, [file_id]	
						, [logical_name]
						, [data_space_id]
						, [type_desc]
						, [max_size]
						, [growth]
						, [is_percent_growth]
						, [physical_name]
						, [size])
	SELECT f.database_id
		, f.file_id
		, f.name AS logical_name
		, f.data_space_id
		, f.type_desc 
		, f.max_size
		, f.growth
		, f.is_percent_growth
		, f.physical_name
		, f.size
	FROM sys.master_files AS f

INSERT INTO #dbs (database_id, database_name)
	SELECT database_id
			, name 
		FROM sys.databases
		WHERE state = 0 
			AND source_database_id IS NULL
			AND @dbname IS NULL
	UNION ALL 
	SELECT database_id
			, name 
		FROM sys.databases 
		WHERE state = 0 
			AND name LIKE @dbname
		ORDER BY name			

SET @numDBs = @@ROWCOUNT

WHILE @countDBs <= @numDBs BEGIN

	SELECT @db = database_name 
		FROM #dbs 
		WHERE ID = @countDBs

	SET @sqlstring	= N'
		USE ' + QUOTENAME(@db) + N'

		UPDATE f	
			SET f.[filegroup] = ISNULL(sp.name, ''Not Applicable'')
				, f.[is_FG_readonly] = CASE WHEN FILEGROUPPROPERTY ( sp.name , ''IsReadOnly'' ) = 1 THEN ''YES'' ELSE ''NO'' END
				, f.[spaceUsed] = CONVERT(BIGINT, FILEPROPERTY(f.logical_name, ''SpaceUsed'')) 
				, f.[size] = dbf.[size]
			FROM #filesUsage AS f
				LEFT JOIN sys.data_spaces AS sp
					ON sp.data_space_id = f.data_space_id
				LEFT JOIN sys.database_files AS dbf
					ON dbf.file_id = f.file_id
						AND f.database_id = DB_ID()
			WHERE database_id = DB_ID()									
	'
	BEGIN TRY
		EXEC sp_executesql @sqlstring
	END TRY
	BEGIN CATCH
	END CATCH
	
	SET @countDBs = @countDBs + 1
END

SELECT	f.database_id
		, DB_NAME(f.database_id) AS database_name
		, f.file_id
		, f.[logical_name]
		, f.type_desc
		, f.[filegroup]
		, f.[is_FG_readonly]
		, CONVERT( DECIMAL(10,2), (f.size * 8. / 1024), 0 ) AS size_mb
		, CONVERT( DECIMAL(10,2), (f.spaceUsed * 8. / 1024), 0 ) AS used_mb
		, CASE WHEN f.growth = 0 THEN 'None'
			ELSE 
				'By ' + 
				CASE 
					WHEN is_percent_growth = 1 THEN CONVERT(VARCHAR,growth) + '%'
					ELSE CONVERT(VARCHAR, (growth * 8 / 1024)) + ' MB'
				END + ', ' +
				CASE 
					WHEN f.max_size = 0 THEN 'No'
					WHEN f.max_size = -1 THEN 'Unlimited'
					ELSE 'Limited to ' + CONVERT(VARCHAR, (CONVERT(BIGINT,max_size) * 8) / 1024) + ' MB'
				END 
			END AS [AutoGrowth/Maxsize]
		, CONVERT( DECIMAL(10,2), (f.spaceUsed * 100. / f.size) ) AS percentage_used
		, CASE WHEN f.type_desc = 'LOG' THEN d.log_reuse_wait_desc ELSE 'n/a' END AS log_reuse_wait_desc
		, REPLACE (f.physical_name, [tempdb].[dbo].[getFileNameFromPath](f.physical_name), '') AS [Path]
		, [tempdb].[dbo].[getFileNameFromPath](f.physical_name) AS [FileName]
		, CONVERT(DECIMAL(10,2), vs.SizeMB / 1024.) AS DriveSizeGB
		, CONVERT(DECIMAL(10,2), vs.FreeMB / 1024.) AS DriveFreeGB
		, vs.FreeMB * 100 / SizeMB AS DriveFreePercent
		, 'USE ' + QUOTENAME(DB_NAME(f.database_id)) + ' DBCC SHRINKFILE (''' + f.[logical_name] COLLATE DATABASE_DEFAULT + ''', xxx)' AS [ShrinkFile]
		, SizeMB
		, 'USE [master]' + CHAR(10) 
			+ 'GO' + CHAR(10) 
			+ 'ALTER DATABASE' + QUOTENAME(DB_NAME(f.database_id)) 
			+ ' MODIFY FILE(NAME=' + QUOTENAME(f.[logical_name]) + ', FILEGROWTH=' + CASE WHEN (f.size * 8. / 1024) > 10000 THEN '4000'  
																						WHEN (f.size * 8. / 1024) > 4000 THEN '1000'
																						WHEN (f.size * 8. / 1024) > 1000 THEN '500'
																						ELSE '100'
																						END + 'MB)' AS [ModifyGrowth]
	FROM #filesUsage AS f
		INNER JOIN sys.databases AS d
			ON d.database_id = f.database_id
		LEFT JOIN #volume_stats AS vs
			ON tempdb.dbo.getDriveFromFullPath(vs.Drive) = tempdb.dbo.getDriveFromFullPath(f.physical_name)
	WHERE f.type_desc = ISNULL(@fileType, f.type_desc)
		AND source_database_id IS NULL
		AND d.name LIKE ISNULL(@dbname, d.name)
	ORDER BY database_name
			, f.type_desc DESC 
			, file_id

IF OBJECT_ID('tempdb..#dbs')			IS NOT NULL DROP TABLE #dbs

IF OBJECT_ID('tempdb..#filesUsage')		IS NOT NULL DROP TABLE #filesUsage

IF OBJECT_ID('tempdb..#volume_stats')	IS NOT NULL DROP TABLE #volume_stats
OnError:
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[getDriveFromFullPath]
GO
DROP FUNCTION [dbo].[getFileNameFromPath]
GO