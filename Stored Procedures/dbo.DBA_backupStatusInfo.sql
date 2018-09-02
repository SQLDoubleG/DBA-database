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
-- Create date: 20/05/2015
-- Description:	Returns databases which have failed to complaint to their backup schedule 
--
-- Parameters:
--
-- Change Log:	
--				26/04/2016	RAG	Changed check for last schedule backup as the column is no bitwise anymore
--				03/05/2016	RAG	Added new check for scheduled backup during last 7 days
--				10/08/2016	RAG	Added @dbname and @numdays to give more flexibility
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_backupStatusInfo]
	@dbname		SYSNAME		= NULL
	, @numdays	SMALLINT	= 7
AS
BEGIN

	SET NOCOUNT ON 

	IF OBJECT_ID('tempdb..#All_Dates') IS NOT NULL DROP TABLE #All_Dates

	-- Recursive cte to get last seven days
	;WITH LastSevenDays AS(
		SELECT CONVERT(DATE, DATEADD(DAY,(-1 * @numdays),GETDATE())) as [date]
		UNION ALL
		SELECT DATEADD(DAY, 1, [date] ) 
			FROM LastSevenDays
			WHERE [date] < DATEADD(DAY,-2,GETDATE())
	) 

	-- Create temp table to get 1 row per date / database in this server
	SELECT Dates.date, Dbs.server_name, Dbs.name, Dbs.BackupSchedule
		INTO #All_Dates
		FROM LastSevenDays AS Dates
			CROSS APPLY DBA.dbo.DatabaseInformation AS Dbs 
		WHERE Dbs.server_name = @@SERVERNAME
		

	;WITH backupHistory AS (
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
					, CONVERT(DATE, b.backup_start_date) AS backup_date
					, b.backup_start_date
					, b.backup_finish_date
					--, b.media_set_id
					--, mf.physical_device_name
					--, ROW_NUMBER() OVER (PARTITION BY database_name ORDER BY backup_set_id DESC) AS RowNum			
				FROM msdb.dbo.backupset as b
				WHERE b.server_name = @@SERVERNAME
					AND b.type IN ('D', 'I')
					AND b.database_name = ISNULL(@dbname, b.database_name)
					AND b.backup_start_date BETWEEN CONVERT(DATE, DATEADD(DAY, (-1 * @numdays), GETDATE())) AND CONVERT(DATE, GETDATE())
		)


	SELECT d.date
			, d.server_name
			, d.name AS database_name
			, SUBSTRING(BackupSchedule, DATEPART(WEEKDAY,[date]) , 1) ScheduledBackupType
			, b.backup_type
			, CASE WHEN has_backup_checksums = 1 THEN 'Yes' ELSE 'No' END AS has_backup_checksums
			, CONVERT( INT, backup_size / 1024 /1024 ) AS size_MB
			, CONVERT( INT, compressed_backup_size / 1024 /1024 ) AS compressed_size_MB
			, CONVERT( DECIMAL(10,2), backup_size / 1024. /1024 /1024 ) AS size_GB
			, CONVERT( DECIMAL(10,2), compressed_backup_size / 1024. / 1024 /1024 ) AS compressed_size_GB
			, CONVERT( DECIMAL(10,2), 100 - ( ( compressed_backup_size * 100 ) / backup_size ) ) AS compression_ratio
			, CONVERT( DECIMAL(10,2), (compressed_backup_size / 1024. / 1024) / (DATEDIFF(SECOND, backup_start_date, backup_finish_date ) + 1) ) AS MB_per_sec
			, backup_start_date			
			, backup_finish_date			
			, DBA.dbo.formatSecondsToHR( DATEDIFF(SECOND,backup_start_date, backup_finish_date) ) AS duration
		FROM #All_Dates AS d
			LEFT JOIN backupHistory AS b
				ON d.date = b.backup_date
					AND d.name = b.database_name
		WHERE d.name = ISNULL(@dbname, d.name)
		ORDER BY d.name, d.date ASC  

END 



GO
