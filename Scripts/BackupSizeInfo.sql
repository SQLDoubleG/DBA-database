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
-- Create date: 16/05/2013
-- Description:	Returns useful info about a number of last backup(s)
--				for a given database or all if not specified
--
-- Parameters:
--				@dbname
--				@onlyFullBkp, set to 1 to display only full backups, if set to 0, will display any backup
--				@numBkp, specify the number of backups to display per database (from newest to oldest)
--
-- Log History:	25/09/2013 RAG 
--					Changed the query to display backups distributed in more than 1 file as 1 single backup
--					and physical_device_name will concatenate all files for that backup
--				19/12/2013 RAG Changed to use LIKE in the databases query to use wildcards in the parameter
--				04/08/2014 RAG Added a basic restore statement
--				26/04/2016 RAG Changed parameter @onlyFullBkp for @backupType
--				30/09/2018 RAG Created new Dependencies section
--								- Added dependant function as tempdb object 
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
-- =============================================
-- END of Dependencies
-- =============================================
USE [master]
GO
DECLARE @dbname			SYSNAME = NULL
		, @backupType	CHAR(1) = NULL
		, @numBkp		INT = 1
	
SET NOCOUNT ON

IF @backupType IS NOT NULL AND @backupType NOT IN ('D', 'I', 'L', 'F', 'G', 'P', 'Q') BEGIN
	RAISERROR ('The parameter @backupType can only be one of these values
D-> Database
I-> Differential database
L-> Log
F-> File or filegroup
G-> Differential file
P-> Partial
Q-> Differential partial
NULL -> All types will be included', 16, 0) WITH NOWAIT
	GOTO OnError
END

SET @numBkp			= ISNULL(@numBkp, 1) 

;WITH cte AS (
	SELECT	b.server_name
			, b.database_name
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
			, ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_set_id DESC) AS RowNum			
		FROM msdb.dbo.backupset as b
			--INNER JOIN msdb.dbo.backupmediafamily as mf
			--	ON mf.media_set_id = b.media_set_id
		WHERE database_name LIKE ISNULL(@dbname, database_name)
			AND b.server_name = @@SERVERNAME
			AND type = ISNULL(@backupType, type)
)

SELECT 	server_name
		, database_name
		, STUFF( (SELECT ', ' + physical_device_name FROM msdb.dbo.backupmediafamily as mf WHERE mf.media_set_id = cte.media_set_id FOR XML PATH('')), 1,2,'' ) AS physical_device_name
		, backup_type
		, CASE WHEN has_backup_checksums = 1 THEN 'Yes' ELSE 'No' END AS has_backup_checksums
		, CONVERT( INT, backup_size / 1024 /1024 ) AS size_MB
		, CONVERT( INT, compressed_backup_size / 1024 /1024 ) AS compressed_size_MB
		, CONVERT( DECIMAL(10,2), backup_size / 1024. /1024 /1024 ) AS size_GB
		, CONVERT( DECIMAL(10,2), compressed_backup_size / 1024. / 1024 /1024 ) AS compressed_size_GB
		, CONVERT( DECIMAL(10,2), 100 - ( ( compressed_backup_size * 100 ) / backup_size ) ) AS compression_ratio
		, CONVERT( DECIMAL(10,2), (compressed_backup_size / 1024. / 1024) / (DATEDIFF(SECOND, backup_start_date, backup_finish_date ) + 1) ) AS MB_per_sec
		, backup_finish_date			
		, tempdb.dbo.formatSecondsToHR( DATEDIFF(SECOND,backup_start_date, backup_finish_date) ) AS duration
		, 'RESTORE DATABASE ' + QUOTENAME(database_name) + CHAR(10) + CHAR(9) + 'FROM ' + 
			STUFF( (SELECT ', DISK = ''' + physical_device_name + '''' + CHAR(10) + CHAR(9)
						FROM msdb.dbo.backupmediafamily as mf WHERE mf.media_set_id = cte.media_set_id FOR XML PATH('')), 1,2,'' )  AS RESTORE_BACKUP
	FROM cte
	WHERE RowNum <= @numBkp
	ORDER BY database_name ASC
		, backup_finish_date DESC
OnError:
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[formatSecondsToHR]
GO

