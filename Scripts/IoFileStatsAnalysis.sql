SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2021 Raul Gonzalez, @SQLDoubleG (RAG)
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
-- Author:		Raul Gonzalez, @SQLDoubleG (RAG)
-- Create date: 26/03/2021
-- Description:	This script will return information collected in sys.dm_io_virtual_file_stats
--
-- Assumptions:	sys.dm_io_virtual_file_stats is reset upon SQL Server restart
--				This script will only check for reads on DATA files
--
-- Parameters:	
--				- @dbname
--				- @topNrows
--
-- Log History:	
--				26/03/2021  RAG - Created
--
-- =============================================
SET NOCOUNT ON

DECLARE @dbname	    SYSNAME			= NULL
DECLARE @topNrows	INT				= NULL

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

DECLARE @total	BIGINT = (SELECT SUM(num_of_bytes_read) FROM sys.dm_io_virtual_file_stats (NULL, NULL) WHERE file_id <> 2)
DECLARE @boot	BIGINT = (SELECT ms_ticks FROM sys.dm_os_sys_info)

SELECT  DATEADD(SECOND, -(@boot/1000), GETDATE()) AS [date_from]
		,SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024 / 1024 / 1024	))) AS tb_read
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024 / 1024			))) AS gb_read
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024					))) AS mb_read
		, SUM(CONVERT(DECIMAL(15,2), (size_on_disk_bytes / 1024. / 1024 / 1024			))) AS size_on_disk_gb
		, SUM(CONVERT(DECIMAL(15,2), (size_on_disk_bytes / 1024. / 1024					))) AS size_on_disk_mb
		, CONVERT(DECIMAL(10,2), (SUM(num_of_bytes_read) / MAX(@boot)) / 1024. / 1024 / 1024 * 1000 * 3600			) AS gb_read_hour
		, CONVERT(DECIMAL(10,2), (SUM(num_of_bytes_read) / MAX(@boot)) / 1024. / 1024 / 1024 / 1024 * 1000 * 3600	) AS tb_read_hour
		-- How many times their data size per hour
		, CONVERT(DECIMAL(15,2), (SUM((num_of_bytes_read / (@boot / 1000. / 3600)))) / SUM(size_on_disk_bytes)) AS ratio_read_hour

FROM sys.dm_io_virtual_file_stats (NULL, NULL)
WHERE file_id <> 2
ORDER BY mb_read DESC

SET @topNrows = ISNULL(@topNrows, 2140000000)

SELECT  DATEADD(SECOND, -(@boot/1000), GETDATE()) AS [date_from]
		, DB_NAME(database_id) AS [db_name]
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024 / 1024 / 1024	))) AS tb_read
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024 / 1024			))) AS gb_read
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / 1024. / 1024					))) AS mb_read
		, SUM(CONVERT(DECIMAL(15,2), (size_on_disk_bytes / 1024. / 1024 / 1024			))) AS size_on_disk_gb
		, SUM(CONVERT(DECIMAL(15,2), (size_on_disk_bytes / 1024. / 1024					))) AS size_on_disk_mb
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / (@boot / 1000. / 3600) / 1024 / 1024 /1024))) AS gb_read_hour
		, SUM(CONVERT(DECIMAL(15,2), (num_of_bytes_read / (@boot / 1000. / 3600) / 1024 / 1024 /1024 / 1024))) AS tb_read_hour
		-- How many times their data size per hour
		, CONVERT(DECIMAL(15,2), (SUM((num_of_bytes_read / (@boot / 1000. / 3600)))) / SUM(size_on_disk_bytes)) AS ratio_read_hour
		, CONVERT(DECIMAL(15,2), (SUM(num_of_bytes_read) * 1.) / @total * 100)	AS percentage_reads
FROM sys.dm_io_virtual_file_stats (NULL, NULL)
WHERE file_id <> 2
GROUP BY database_id
ORDER BY mb_read DESC
