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
-- Create date: 16/05/2013
-- Description:	Returns useful info about a number of last backup(s)
--				for a given database or all if not specified
--
-- Parameters:
--				@dbname
--				@onlyFullBkp, set to 1 to display only full backups, if set to 0, will display any backup
--				@numBkp, specify the number of backups to display per database (from newest to oldest)
--
-- Log History:	25/09/2013 RAG	- Changed the query to display backups distributed in more than 1 file as 1 single backup
--									and physical_device_name will concatenate all files for that backup
--				19/12/2013 RAG	- Changed to use LIKE in the databases query to use wildcards in the parameter
--				04/08/2014 RAG	- Added a basic restore statement
--				26/04/2016 RAG	- Changed parameter @onlyFullBkp for @backupType
--				30/09/2018 RAG	- Created new Dependencies section
--								- Added dependant function as tempdb object 
--				10/10/2018 RAG	- Added backup type X that will all types expect LOG backups
--				14/10/2018 RAG	- Modified the restore command to consider RESTORE LOG 
-- 								- Modified the restore command to be by default WITH NORECOVERY
--								- Added @orderBy to sort ascending or descending to allow copy paste 
-- 									the restore commands in the right order
--								- Changed order of the returned columns to have finished date at first glance
--				16/10/2018 RAG	- Changed the behaviour of @orderBy so it will affect the final resultset which will be
-- 									always the newest TOP (@numBkp) rows
--				20/11/2018 RAG	- Added join to sys.databases so now we get all databases in the server,
--									 regardless have been ever backed up or not.
--								- Added is_preffered replica using [fn_hadr_backup_is_preferred_replica]
--				11/03/2020 RAG	- Added MOVE xx TO xx and parameters @newDataPath and @newLogPath for easy restores
--				11/06/2020 RAG	- Added RESTORE FILESLISTONLY column and REPLACE option
-- =============================================
-- =============================================
-- Dependencies:This Section will create on tempdb any dependant function
-- =============================================
USE tempdb
GO
CREATE FUNCTION [dbo].[formatSecondsToHR](
	@nSeconds INT
)
RETURNS VARCHAR(24)
AS
BEGIN
	-- Declare the return variable here
	DECLARE @R VARCHAR(24)

	SET @R = ISNULL(NULLIF(CONVERT(VARCHAR(24), @nSeconds / 3600 / 24 ),'0') + '.', '') + 
				RIGHT('00' + CONVERT(VARCHAR(24), @nSeconds / 3600 % 24 ), 2) + ':' + 
				RIGHT('00' + CONVERT(VARCHAR(24), @nSeconds / 60 % 60), 2) + ':' + 
				RIGHT('00' + CONVERT(VARCHAR(24), @nSeconds % 60), 2)

	RETURN @R

END
GO
CREATE FUNCTION [dbo].[getFileNameFromPath](
	@path NVARCHAR(256)
)
RETURNS sysname
AS
BEGIN

	DECLARE @slashPos	INT		= CASE WHEN CHARINDEX( '\', REVERSE(@path) ) > 0 THEN CHARINDEX( '\', REVERSE(@path) ) -1 ELSE LEN(@path) END
	-- \\' 
	RETURN RIGHT( @path, @slashPos ) 
END
GO
-- =============================================
-- END of Dependencies
-- =============================================
USE [master]
GO
DECLARE @dbname			sysname --= 'msdb'
		, @backupType	CHAR(1) = 'X'
		, @numBkp		INT = 1
		, @orderBy		VARCHAR(10) = 'ASC'
		, @newDataPath	NVARCHAR(512) = NULL -- 'X:\Data'
		, @newLogPath	NVARCHAR(512) = NULL -- 'X:\Logs'
		, @replace		BIT = 0 -- Set to 1 to add WITH REPLACE
	
DECLARE @sqlstring NVARCHAR(4000)

SET @numBkp		= ISNULL(@numBkp, 1) 
SET @orderBy	= ISNULL(@orderBy, 'DESC') 
SET @newDataPath= @newDataPath + (CASE WHEN RIGHT(@newDataPath, 1) <> '\' THEN '\' ELSE '' END)	-- \\' 
SET @newLogPath	= @newLogPath + (CASE WHEN RIGHT(@newLogPath, 1) <> '\' THEN '\' ELSE '' END)	-- \\' 


IF @backupType IS NOT NULL AND @backupType NOT IN ('D', 'I', 'L', 'F', 'G', 'P', 'Q', 'X') BEGIN
	RAISERROR ('The parameter @backupType can only be one of these values
D-> Database
I-> Differential database
L-> Log
F-> File or filegroup
G-> Differential file
P-> Partial
Q-> Differential partial
X-> All types except LOG
NULL -> All types will be included', 16, 0) WITH NOWAIT
	GOTO OnError
END

IF @orderBy NOT IN ('ASC', 'DESC') BEGIN
	RAISERROR ('The parameter @orderBy can only be one of these values
ASC-> To sort by date asceding
DESC-> To sort by date asceding', 16, 0) WITH NOWAIT
	GOTO OnError
END

CREATE TABLE #is_preferred_replica (
	database_id INT NOT NULL
	, is_preferred_replica TINYINT NOT NULL)

IF ISNULL(CONVERT(TINYINT, SERVERPROPERTY('IsHadrEnabled')), 0) = 1 BEGIN 
	SET @sqlstring = N'SELECT database_id, sys.fn_hadr_backup_is_preferred_replica(name) FROM sys.databases'
	INSERT INTO #is_preferred_replica (database_id, is_preferred_replica)
	EXECUTE sys.sp_executesql @stmt = @sqlstring
END
ELSE BEGIN
	INSERT INTO #is_preferred_replica (database_id, is_preferred_replica)
	SELECT database_id, 1 FROM sys.databases
END
	
;WITH cte AS (
	SELECT	b.server_name
			, b.database_name
			, b.type
			,	CASE 
					WHEN b.type = 'D' THEN 'Database'
					WHEN b.type = 'I' THEN 'Differential database'
					WHEN b.type = 'L' THEN 'Log'
					WHEN b.type = 'F' THEN 'File or filegroup'
					WHEN b.type = 'G' THEN 'Differential file'
					WHEN b.type = 'P' THEN 'Partial'
					WHEN b.type = 'Q' THEN 'Differential partial'
				END AS backup_type
			, b.backup_size
			, b.has_backup_checksums
			, b.compressed_backup_size 
			, b.backup_start_date
			, b.backup_finish_date
			, b.media_set_id
			--, mf.physical_device_name
			, ROW_NUMBER() OVER (PARTITION BY b.database_name ORDER BY b.backup_set_id DESC) AS RowNum			
		FROM msdb.dbo.backupset AS b
			--INNER JOIN msdb.dbo.backupmediafamily as mf
			--	ON mf.media_set_id = b.media_set_id
		WHERE b.database_name LIKE ISNULL(@dbname, b.database_name)
			AND b.server_name = @@SERVERNAME
			AND (b.type = ISNULL(@backupType, b.type) OR (@backupType = 'X' AND b.type <> 'L'))
)

SELECT 	ISNULL(cte.server_name, @@SERVERNAME) AS server_name
		, d.name AS database_name
		, CASE WHEN pr.is_preferred_replica = 1 THEN 'Yes' ELSE 'No' END AS is_preferred_replica
		, ISNULL(cte.backup_type, 'n/a') AS backup_type
		, d.create_date
		, d.state_desc
		, d.recovery_model_desc
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(DATETIME2(0), cte.backup_finish_date)), '-') AS backup_finish_date
		, ISNULL(STUFF((SELECT ', ' + mf.physical_device_name 
							FROM msdb.dbo.backupmediafamily AS mf 
							WHERE mf.media_set_id = cte.media_set_id 
							FOR XML PATH('')), 1,2,'' ), '-') AS physical_device_name
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(INT, cte.backup_size / 1024 /1024 )), '-') AS size_MB
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(INT, cte.compressed_backup_size / 1024 /1024 )), '-') AS compressed_size_MB
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(DECIMAL(10,2), cte.backup_size / 1024. /1024 /1024 )), '-') AS size_GB
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(DECIMAL(10,2), cte.compressed_backup_size / 1024. / 1024 /1024 )), '-') AS compressed_size_GB
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(DECIMAL(10,2), 100 - ( ( cte.compressed_backup_size * 100 ) / cte.backup_size ) )), '-') AS compression_ratio
		, ISNULL(CONVERT(VARCHAR(100), CONVERT(DECIMAL(10,2), (cte.compressed_backup_size / 1024. / 1024) / (DATEDIFF(SECOND, cte.backup_start_date, cte.backup_finish_date ) + 1) )), '-') AS MB_per_sec
		, ISNULL(CONVERT(VARCHAR(100), tempdb.dbo.formatSecondsToHR( DATEDIFF(SECOND,cte.backup_start_date, cte.backup_finish_date) )), '-') AS duration
		, CASE WHEN cte.has_backup_checksums = 1 THEN 'Yes' ELSE 'No' END AS has_backup_checksums
		, ISNULL('RESTORE FILELISTONLY FROM ' + 
			STUFF( (SELECT ', DISK = ''' + mf.physical_device_name + '''' + CHAR(10) + CHAR(9)
						FROM msdb.dbo.backupmediafamily AS mf WHERE mf.media_set_id = cte.media_set_id FOR XML PATH('')), 1,2,'' ), '--')
			AS RESTORE_FILELISTONLY
		, ISNULL('RESTORE ' + CASE WHEN cte.type = 'L' THEN 'LOG ' ELSE 'DATABASE ' END + QUOTENAME(cte.database_name) + CHAR(10) + CHAR(9) + 'FROM ' + 
			STUFF( (SELECT ', DISK = ''' + mf.physical_device_name + '''' + CHAR(10) + CHAR(9)
						FROM msdb.dbo.backupmediafamily AS mf WHERE mf.media_set_id = cte.media_set_id FOR XML PATH('')), 1,2,'' ) + 'WITH NORECOVERY, STATS' 
			+ CASE WHEN @replace = 1 AND cte.type = 'D'  THEN ', REPLACE' ELSE '' END
			+ CASE WHEN cte.type = 'D' THEN 
					(SELECT ', MOVE ''' + mf.name  + ''' TO ''' + (
						CASE WHEN mf.type_desc = 'ROWS' AND @newDataPath IS NOT NULL 
								THEN @newDataPath + tempdb.dbo.getFileNameFromPath(mf.physical_name)
							 WHEN mf.type_desc = 'LOG' AND @newLogPath IS NOT NULL 
								THEN @newLogPath + tempdb.dbo.getFileNameFromPath(mf.physical_name)
							ELSE mf.physical_name
						END + '''' + CHAR(10) + CHAR(9))
					FROM sys.master_files AS mf WHERE DB_NAME(mf.database_id) = cte.database_name FOR XML PATH(''))
					ELSE ''
				END, '--')
		AS RESTORE_BACKUP
	FROM sys.databases AS d
		LEFT JOIN cte
			ON d.name = cte.database_name
				AND cte.RowNum <= @numBkp
		LEFT JOIN #is_preferred_replica AS pr
			ON pr.database_id = d.database_id
	WHERE d.database_id <> 2
		AND d.name LIKE ISNULL(@dbname, d.name)
	ORDER BY database_name ASC
		-- RowNum is descending, so we need to invert the order, this is not a mistake!
		, CASE WHEN @orderBy = 'ASC' THEN cte.RowNum ELSE NULL END DESC
		, CASE WHEN @orderBy = 'DESC' THEN cte.RowNum ELSE NULL END ASC 

DROP TABLE #is_preferred_replica

OnError:
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[formatSecondsToHR]
GO
DROP FUNCTION [dbo].[getFileNameFromPath]
GO
