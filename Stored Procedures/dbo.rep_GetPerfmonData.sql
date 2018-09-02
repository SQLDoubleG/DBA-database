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
-- Author:		Raul Gonzalez @SQLDoubleG
-- Create date: 07/02/2018
-- Description:	Displays perfmon information 
--
-- Parameters:
--				The different parameters are cummulative from wider partitions to smaller. If all partitions are false
--				the report will return every row for the selected period.
--
--				@dbname					-> Mandatory, this will be the name of the database where the info is stored
--				@partitionByYear		-> The info will be diplayed per year
--				@partitionByQuarter		-> The info will be diplayed per quarter of the year
--				@partitionByMonth		-> The info will be diplayed per month
--				@partitionByWeek		-> The info will be diplayed per Week of the year
--				@partitionByDay			-> The info will be diplayed per day
--				@partitionByDayOfMonth	-> The info will be diplayed per day of the month
--				@partitionByDayOfWeek	-> The info will be diplayed per day of the week
--				@partitionByAMPM		-> The info will be diplayed per AM-PM
--				@partitionByHour		-> The info will be diplayed per hour of the day
--				@partitionByMinute		-> The info will be diplayed per minute of the day
--				@DateFrom				-> Mandatory  
--				@DateTo					-> Mandatory
--				@IsWorkingHours			-> Possible values
--											- 1 will include only values from 7 to 19
--											- 0 will include only periods from 19 to 7
--											- NULL will include all rows
--				@IsWeekend				-> Possible values
--											- 1 will include only values from Monday to Friday
--											- 0 will include only periods from Saturday to Sunday
--											- NULL will include all rows
--
-- Change Log:	
--
-- Permissions:
--
--				GRANT EXECUTE ON OBJECT::dbo.rep_GetPerfmonData TO [reporting]
-- 
-- =============================================
CREATE PROCEDURE [dbo].[rep_GetPerfmonData]
	@dbname						SYSNAME
	, @partitionByYear			BIT = NULL
	, @partitionByQuarter		BIT = NULL
	, @partitionByMonth			BIT = NULL
	, @partitionByWeek			BIT = NULL
	, @partitionByDay			BIT = NULL
	, @partitionByDayOfMonth	BIT = NULL 
	, @partitionByDayOfWeek		BIT = NULL 
	, @partitionByAMPM			BIT = NULL
	, @partitionByHour			BIT = NULL 
	, @partitionByMinute		BIT = NULL 
	, @DateFrom					DATE
	, @DateTo					DATE
	, @IsWorkingHours			BIT = NULL
	, @IsWeekend				BIT = NULL
WITH EXECUTE AS 'dbo'
AS
BEGIN

DECLARE @SQL				NVARCHAR(MAX)
DECLARE @SQLBatchRSec		NVARCHAR(MAX)
DECLARE @SQLUserConn		NVARCHAR(MAX)
DECLARE @SQLMemGrantsPen	NVARCHAR(MAX)
DECLARE @PartitionColumns	NVARCHAR(MAX) = N''
DECLARE @GroupByColumns		NVARCHAR(MAX) = N''
DECLARE @BatchRSec			NVARCHAR(MAX)
DECLARE @UserConn			NVARCHAR(MAX)
DECLARE @MemGrantsPen		NVARCHAR(MAX)
DECLARE @MaxBatchRSec		NVARCHAR(MAX)
DECLARE @MaxUserConn		NVARCHAR(MAX)
DECLARE @MaxMemGrantsPen	NVARCHAR(MAX)
 
IF DB_ID(@dbname) IS NULL BEGIN
	RETURN -100
END

IF OBJECT_ID('#t') IS NOT NULL DROP TABLE #t

CREATE TABLE #t (
	ID															INT IDENTITY	NOT NULL PRIMARY KEY
	, [ComputerName]											sysname			NOT NULL
	, [CounterDateTime]											DATETIME2(3)	NULL
	, [CalendarYear]											SMALLINT		NULL
	, [CalendarQuarter]											TINYINT			NULL
	, [MonthOfYear]												TINYINT			NULL
	, [MonthName]												VARCHAR(10)		NULL
	, [WeekOfYear]												TINYINT			NULL
	, [CounterDate]												DATE			NULL
	, [DayOfMonth]												TINYINT			NULL
	, [DayOfWeek]												TINYINT			NULL
	, [DayOfWeekName]											VARCHAR(10)		NULL
	, [AM-PM]													CHAR(2)			NULL
	, [HourOfDay]												TINYINT			NULL
	, [HoursMinutes]											TIME(0)			NULL
	, [_Total SQL Statistics\Batch Requests/sec]				INT				NOT NULL
	, [_Total General Statistics\User Connections]				INT				NOT NULL
	, [_Total Memory Manager\Memory Grants Pending]				INT				NOT NULL
	, [Memory\Available MBytes]									DECIMAL(10, 2)	NOT NULL
	, [Processor\% Processor Time (_Total)]						DECIMAL(10, 2)	NOT NULL
	, [Paging File\% Usage (_Total)]							DECIMAL(10, 2)	NOT NULL
	, [PhysicalDisk\Avg. Disk Queue Length (_Total)]			DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Avg. Disk Read Queue Length (_Total)]		DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Avg. Disk sec/Read (_Total)]				DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Avg. Disk sec/Write (_Total)]				DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Avg. Disk Write Queue Length (_Total)]		DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Current Disk Queue Length (_Total)]			DECIMAL(10, 3)	NOT NULL
	, [PhysicalDisk\Disk Reads/sec (_Total)]					DECIMAL(10, 2)	NOT NULL
	, [PhysicalDisk\Disk Writes/sec (_Total)]					DECIMAL(10, 2)	NOT NULL
	, [Max_Total SQL Statistics\Batch Requests/sec]				INT				NOT NULL
	, [Max_Total General Statistics\User Connections]			INT				NOT NULL
	, [Max_Total Memory Manager\Memory Grants Pending]			INT				NOT NULL
	, [Min Memory\Available MBytes]								DECIMAL(10, 2)	NOT NULL
	, [Max Processor\% Processor Time (_Total)]					DECIMAL(10, 2)	NOT NULL
	, [Max Paging File\% Usage (_Total)]						DECIMAL(10, 2)	NOT NULL
	, [Max PhysicalDisk\Avg. Disk Queue Length (_Total)]		DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Avg. Disk Read Queue Length (_Total)]	DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Avg. Disk sec/Read (_Total)]			DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Avg. Disk sec/Write (_Total)]			DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Avg. Disk Write Queue Length (_Total)]	DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Current Disk Queue Length (_Total)]		DECIMAL(10, 3)	NOT NULL
	, [Max PhysicalDisk\Disk Reads/sec (_Total)]				DECIMAL(10, 2)	NOT NULL
	, [Max PhysicalDisk\Disk Writes/sec (_Total)]				DECIMAL(10, 2)	NOT NULL
);

SET @partitionByYear		= ISNULL(@partitionByYear			, 0)
SET @partitionByQuarter		= ISNULL(@partitionByQuarter		, 0)
SET @partitionByMonth		= ISNULL(@partitionByMonth			, 0)
SET @partitionByWeek		= ISNULL(@partitionByWeek			, 0)
SET @partitionByDay			= ISNULL(@partitionByDay			, 0)
SET @partitionByDayOfMonth	= ISNULL(@partitionByDayOfMonth		, 0)
SET @partitionByDayOfWeek	= ISNULL(@partitionByDayOfWeek		, 0)
SET @partitionByAMPM		= ISNULL(@partitionByAMPM			, 0)
SET @partitionByHour		= ISNULL(@partitionByHour			, 0)
SET @partitionByMinute		= ISNULL(@partitionByMinute			, 0)

SET @PartitionColumns	+= (CASE WHEN @partitionByYear = 1			THEN N', [d].[CalendarYear]'					ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByQuarter = 1		THEN N', [d].[CalendarQuarter]'					ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByMonth = 1			THEN N', [d].[MonthOfYear], [d].[MonthName]'	ELSE N', NULL, NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByWeek = 1			THEN N', [d].[WeekOfYear]'						ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByDay = 1			THEN N', [p].[CounterDate]'						ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByDayOfMonth = 1	THEN N', [d].[DayOfMonth]'						ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByDayOfWeek = 1		THEN N', [d].[DayOfWeek], [d].[DayOfWeekName]'	ELSE N', NULL, NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByAMPM = 1			THEN N', [t].[AM-PM]'							ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByHour = 1			THEN N', [t].[HourOfDay]'						ELSE N', NULL' END)
SET @PartitionColumns	+= (CASE WHEN @partitionByMinute = 1		THEN N', [t].[HoursMinutes]'					ELSE N', NULL' END)

SET @GroupByColumns		+= (CASE WHEN @partitionByYear = 1			THEN N', [d].[CalendarYear]'					ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByQuarter = 1		THEN N', [d].[CalendarQuarter]'					ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByMonth = 1			THEN N', [d].[MonthOfYear], [d].[MonthName]'	ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByWeek = 1			THEN N', [d].[WeekOfYear]'						ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByDay = 1			THEN N', [p].[CounterDate]'						ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByDayOfMonth = 1	THEN N', [d].[DayOfMonth]'						ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByDayOfWeek = 1		THEN N', [d].[DayOfWeek], [d].[DayOfWeekName]'	ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByAMPM = 1			THEN N', [t].[AM-PM]'							ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByHour = 1			THEN N', [t].[HourOfDay]'						ELSE N'' END)
SET @GroupByColumns		+= (CASE WHEN @partitionByMinute = 1		THEN N', [t].[HoursMinutes]'					ELSE N'' END)

-- if there is no partitions, use date time
SET @PartitionColumns	= (CASE WHEN 	ISNULL(@partitionByYear			, 0) = 0
									AND ISNULL(@partitionByQuarter		, 0) = 0
									AND ISNULL(@partitionByMonth		, 0) = 0
									AND ISNULL(@partitionByWeek			, 0) = 0
									AND ISNULL(@partitionByDay			, 0) = 0
									AND ISNULL(@partitionByDayOfMonth	, 0) = 0
									AND ISNULL(@partitionByDayOfWeek	, 0) = 0
									AND ISNULL(@partitionByAMPM			, 0) = 0
									AND ISNULL(@partitionByHour			, 0) = 0 
									AND ISNULL(@partitionByMinute		, 0) = 0 
								THEN N', [p].[CounterDateTime], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL ' 
								ELSE N', NULL' + @PartitionColumns 
							END)
SET @GroupByColumns		= (CASE WHEN 	ISNULL(@partitionByYear			, 0) = 0
									AND ISNULL(@partitionByQuarter		, 0) = 0
									AND ISNULL(@partitionByMonth		, 0) = 0
									AND ISNULL(@partitionByWeek			, 0) = 0
									AND ISNULL(@partitionByDay			, 0) = 0
									AND ISNULL(@partitionByDayOfMonth	, 0) = 0
									AND ISNULL(@partitionByDayOfWeek	, 0) = 0
									AND ISNULL(@partitionByAMPM			, 0) = 0
									AND ISNULL(@partitionByHour			, 0) = 0 
									AND ISNULL(@partitionByMinute		, 0) = 0 
								THEN N', [p].[CounterDateTime]' 
								ELSE @GroupByColumns
							END)

--==================================================================================================
-- Get SQL Server related counters
--==================================================================================================

SET @SQLBatchRSec = N'USE ' + QUOTENAME(@dbname) + '
				SET @BatchRSec = 
				(SELECT N'', AVG(CONVERT (INT, '' +
						STUFF((SELECT N'' + '' + QUOTENAME(ObjectName + N''\'' + CounterName) 
							FROM dbo.CounterDetails 
							WHERE CounterName IN (''Batch Requests/sec'')
							ORDER BY ObjectName, CounterName
							FOR XML PATH('''')), 1, 3, '''') 
						+ '')) AS  [_Total SQL Statistics\Batch Requests/sec] ''
				)'	

EXECUTE sys.sp_executesql 
		@stmt = @SQLBatchRSec
		, @params = N'@BatchRSec NVARCHAR(MAX) OUTPUT'
		, @BatchRSec = @BatchRSec OUTPUT

SET @MaxBatchRSec = REPLACE(@BatchRSec, 'AVG(', 'MAX(')
--==================================================================================================

SET @SQLUserConn = N'USE ' + QUOTENAME(@dbname) + '
				SET @UserConn = 
				(SELECT N'', AVG(CONVERT (INT, '' +
						STUFF((SELECT N'' + '' + QUOTENAME(ObjectName + N''\'' + CounterName) 
							FROM dbo.CounterDetails 
							WHERE CounterName IN (''User Connections'')
							ORDER BY ObjectName, CounterName
							FOR XML PATH('''')), 1, 3, '''') 
						+ '')) AS  [_Total General Statistics\User Connections] ''
				)'	

EXECUTE sys.sp_executesql 
		@stmt = @SQLUserConn
		, @params = N'@UserConn NVARCHAR(MAX) OUTPUT'
		, @UserConn = @UserConn OUTPUT

SET @MaxUserConn = REPLACE(@UserConn, 'AVG(', 'MAX(')

--==================================================================================================

SET @SQLMemGrantsPen = N'USE ' + QUOTENAME(@dbname) + '
				SET @MemGrantsPen = 
				(SELECT N'', AVG(CONVERT (INT, '' +
						STUFF((SELECT N'' + '' + QUOTENAME(ObjectName + N''\'' + CounterName) 
							FROM dbo.CounterDetails 
							WHERE CounterName IN (''Memory Grants Pending'')
							ORDER BY ObjectName, CounterName
							FOR XML PATH('''')), 1, 3, '''') 
						+ '')) AS  [_Total Memory Manager\Memory Grants Pending] ''
				)'	

EXECUTE sys.sp_executesql 
		@stmt = @SQLMemGrantsPen
		, @params = N'@MemGrantsPen NVARCHAR(MAX) OUTPUT'
		, @MemGrantsPen = @MemGrantsPen OUTPUT

SET @MaxMemGrantsPen = REPLACE(@MemGrantsPen, 'AVG(', 'MAX(')

--==================================================================================================	

SET @SQL = N'USE ' + QUOTENAME(@dbname) + '

SELECT p.ComputerName' + 
		@PartitionColumns 
		+ @BatchRSec + @UserConn + @MemGrantsPen + N'		
		, AVG(CONVERT(DECIMAL(10,2), p.[Memory\Available MBytes]							)) AS [Memory\Available MBytes]
		, AVG(CONVERT(DECIMAL(10,2), p.[Processor\% Processor Time (_Total)]				)) AS [Processor\% Processor Time (_Total)]
		, AVG(CONVERT(DECIMAL(10,2), p.[Paging File\% Usage (_Total)]						)) AS [Paging File\% Usage (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Queue Length (_Total)]		)) AS [PhysicalDisk\Avg. Disk Queue Length (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Read Queue Length (_Total)]	)) AS [PhysicalDisk\Avg. Disk Read Queue Length (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk sec/Read (_Total)]			)) AS [PhysicalDisk\Avg. Disk sec/Read (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk sec/Write (_Total)]			)) AS [PhysicalDisk\Avg. Disk sec/Write (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Write Queue Length (_Total)]	)) AS [PhysicalDisk\Avg. Disk Write Queue Length (_Total)]
		, AVG(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Current Disk Queue Length (_Total)]	)) AS [PhysicalDisk\Current Disk Queue Length (_Total)]
		, AVG(CONVERT(DECIMAL(10,2), p.[PhysicalDisk\Disk Reads/sec (_Total)]				)) AS [PhysicalDisk\Disk Reads/sec (_Total)]
		, AVG(CONVERT(DECIMAL(10,2), p.[PhysicalDisk\Disk Writes/sec (_Total)]				)) AS [PhysicalDisk\Disk Writes/sec (_Total)]
		' + @MaxBatchRSec + @MaxUserConn + @MaxMemGrantsPen + N'
		, MIN(CONVERT(DECIMAL(10,2), p.[Memory\Available MBytes]							)) AS [Min Memory\Available MBytes]
		, MAX(CONVERT(DECIMAL(10,2), p.[Processor\% Processor Time (_Total)]				)) AS [Max Processor\% Processor Time (_Total)]
		, MAX(CONVERT(DECIMAL(10,2), p.[Paging File\% Usage (_Total)]						)) AS [Max Paging File\% Usage (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Queue Length (_Total)]		)) AS [Max PhysicalDisk\Avg. Disk Queue Length (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Read Queue Length (_Total)]	)) AS [Max PhysicalDisk\Avg. Disk Read Queue Length (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk sec/Read (_Total)]			)) AS [Max PhysicalDisk\Avg. Disk sec/Read (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk sec/Write (_Total)]			)) AS [Max PhysicalDisk\Avg. Disk sec/Write (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Avg. Disk Write Queue Length (_Total)]	)) AS [Max PhysicalDisk\Avg. Disk Write Queue Length (_Total)]
		, MAX(CONVERT(DECIMAL(10,3), p.[PhysicalDisk\Current Disk Queue Length (_Total)]	)) AS [Max PhysicalDisk\Current Disk Queue Length (_Total)]
		, MAX(CONVERT(DECIMAL(10,2), p.[PhysicalDisk\Disk Reads/sec (_Total)]				)) AS [Max PhysicalDisk\Disk Reads/sec (_Total)]
		, MAX(CONVERT(DECIMAL(10,2), p.[PhysicalDisk\Disk Writes/sec (_Total)]				)) AS [Max PhysicalDisk\Disk Writes/sec (_Total)]
	FROM dbo.Parsed AS p
		 INNER JOIN DBA.dbo.tallyTime			   AS t
			 ON t.FullTime = p.CounterTime
		 INNER JOIN DBA.dbo.tallyDate			   AS d
			 ON d.FullDate = p.CounterDate
	WHERE ( t.IsWorkingHours = @IsWorkingHours OR @IsWorkingHours IS NULL )
		  AND ( d.IsWeekend  = @IsWeekend OR @IsWeekend IS NULL )
		  AND ( p.CounterDate BETWEEN @DateFrom AND @DateTo )
		  '
	+ N' GROUP BY p.ComputerName' + @GroupByColumns
	+ N' ORDER BY p.ComputerName' + @GroupByColumns + N' OPTION(RECOMPILE);'
			
--SELECT @SQL
INSERT INTO #t ([ComputerName], [CounterDateTime], [CalendarYear]
				,[CalendarQuarter], [MonthOfYear], [MonthName], [WeekOfYear], [CounterDate]
				,[DayOfMonth], [DayOfWeek], [DayOfWeekName], [AM-PM], [HourOfDay]
				,[HoursMinutes], [_Total SQL Statistics\Batch Requests/sec]
				,[_Total General Statistics\User Connections]
				,[_Total Memory Manager\Memory Grants Pending], [Memory\Available MBytes]
				,[Processor\% Processor Time (_Total)], [Paging File\% Usage (_Total)]
				,[PhysicalDisk\Avg. Disk Queue Length (_Total)]
				,[PhysicalDisk\Avg. Disk Read Queue Length (_Total)]
				,[PhysicalDisk\Avg. Disk sec/Read (_Total)]
				,[PhysicalDisk\Avg. Disk Write Queue Length (_Total)]
				,[PhysicalDisk\Avg. Disk sec/Write (_Total)]
				,[PhysicalDisk\Current Disk Queue Length (_Total)]
				,[PhysicalDisk\Disk Reads/sec (_Total)], [PhysicalDisk\Disk Writes/sec (_Total)]
				,[Max_Total SQL Statistics\Batch Requests/sec]
				,[Max_Total General Statistics\User Connections]
				,[Max_Total Memory Manager\Memory Grants Pending], [Min Memory\Available MBytes]
				,[Max Processor\% Processor Time (_Total)], [Max Paging File\% Usage (_Total)]
				,[Max PhysicalDisk\Avg. Disk Queue Length (_Total)]
				,[Max PhysicalDisk\Avg. Disk Read Queue Length (_Total)]
				,[Max PhysicalDisk\Avg. Disk sec/Read (_Total)]
				,[Max PhysicalDisk\Avg. Disk sec/Write (_Total)]
				,[Max PhysicalDisk\Avg. Disk Write Queue Length (_Total)]
				,[Max PhysicalDisk\Current Disk Queue Length (_Total)]
				,[Max PhysicalDisk\Disk Reads/sec (_Total)]
				,[Max PhysicalDisk\Disk Writes/sec (_Total)])
EXECUTE sys.sp_executesql 
	@stmt = @SQL
	, @params = N'@IsWorkingHours BIT, @IsWeekend BIT, @DateFrom DATE, @DateTo DATE'
	, @IsWorkingHours = @IsWorkingHours
	, @IsWeekend = @IsWeekend
	, @DateFrom = @DateFrom
	, @DateTo = @DateTo;

SELECT [ComputerName]												AS [ComputerName]
		, [CounterDateTime]											AS [CounterDateTime]
		, [CalendarYear]											AS [CalendarYear]
		, [CalendarQuarter]											AS [CalendarQuarter]
		, [MonthOfYear]												AS [MonthOfYear]	
		, [MonthName]												AS [MonthName]	
		, [WeekOfYear]												AS [WeekOfYear]	
		, [CounterDate]												AS [CounterDate]
		, [DayOfMonth]												AS [DayOfMonth]
		, [DayOfWeek]												AS [DayOfWeek]
		, [DayOfWeekName]											AS [DayOfWeekName]
		, [AM-PM]													AS [AM_PM]
		, [HourOfDay]												AS [HourOfDay]
		, [HoursMinutes]											AS [HoursMinutes]
		, [_Total SQL Statistics\Batch Requests/sec]				AS [SQL_Batch_Requests_Sec_Total]
		, [_Total General Statistics\User Connections]				AS [SQL_Statistics_User_Connections_Total]
		, [_Total Memory Manager\Memory Grants Pending]				AS [SQL_Memory_Grants_Pending_Total]
		, [Memory\Available MBytes]									AS [Memory_Available_MBytes]
		, [Processor\% Processor Time (_Total)]						AS [Processor_Processor_Time_Total]
		, [Paging File\% Usage (_Total)]							AS [Paging_File_Usage_Total]
		, [PhysicalDisk\Avg. Disk Queue Length (_Total)]			AS [PhysicalDisk_Avg_Disk_Queue_Length_Total]
		, [PhysicalDisk\Avg. Disk Read Queue Length (_Total)]		AS [PhysicalDisk_Avg_Disk_Read_Queue_Length_Total]
		, [PhysicalDisk\Avg. Disk sec/Read (_Total)]				AS [PhysicalDisk_Avg_Disk_sec_Read_Total]
		, [PhysicalDisk\Avg. Disk Write Queue Length (_Total)]		AS [PhysicalDisk_Avg_Disk_Write_Queue_Length_Total]
		, [PhysicalDisk\Avg. Disk sec/Write (_Total)]				AS [PhysicalDisk_Avg_Disk_sec_Write_Total]
		, [PhysicalDisk\Current Disk Queue Length (_Total)]			AS [PhysicalDisk_Current_Disk_Queue_Length_Total]
		, [PhysicalDisk\Disk Reads/sec (_Total)]					AS [PhysicalDisk_Disk_Reads_sec_Total]
		, [PhysicalDisk\Disk Writes/sec (_Total)]					AS [PhysicalDisk_Disk_Writes_sec_Total]
		, [Max_Total SQL Statistics\Batch Requests/sec]				AS [Max_SQL_Batch_Requests_Sec_Total]				
		, [Max_Total General Statistics\User Connections]			AS [Max_SQL_Statistics_User_Connections_Total]			
		, [Max_Total Memory Manager\Memory Grants Pending]			AS [Max_SQL_Memory_Grants_Pending_Total]			
		, [Min Memory\Available MBytes]								AS [Min_Memory_Available_MBytes]
		, [Max Processor\% Processor Time (_Total)]					AS [Max_Processor_Processor_Time_Total]
		, [Max Paging File\% Usage (_Total)]						AS [Max_Paging_File_Usage_Total]
		, [Max PhysicalDisk\Avg. Disk Queue Length (_Total)]		AS [Max_PhysicalDisk_Avg_Disk_Queue_Length_Total]
		, [Max PhysicalDisk\Avg. Disk Read Queue Length (_Total)]	AS [Max_PhysicalDisk_Avg_Disk_Read_Queue_Length_Total]
		, [Max PhysicalDisk\Avg. Disk sec/Read (_Total)]			AS [Max_PhysicalDisk_Avg_Disk_sec_Read_Total]
		, [Max PhysicalDisk\Avg. Disk sec/Write (_Total)]			AS [Max_PhysicalDisk_Avg_Disk_Write_Queue_Length_Total]
		, [Max PhysicalDisk\Avg. Disk Write Queue Length (_Total)]	AS [Max_PhysicalDisk_Avg_Disk_sec_Write_Total]
		, [Max PhysicalDisk\Current Disk Queue Length (_Total)]		AS [Max_PhysicalDisk_Current_Disk_Queue_Length_Total]
		, [Max PhysicalDisk\Disk Reads/sec (_Total)]				AS [Max_PhysicalDisk_Disk_Reads_sec_Total]
		, [Max PhysicalDisk\Disk Writes/sec (_Total)]				AS [Max_PhysicalDisk_Disk_Writes_sec_Total]
	FROM #t
	ORDER BY ID;

IF OBJECT_ID('#t') IS NOT NULL DROP TABLE #t
END
GO
GRANT EXECUTE ON  [dbo].[rep_GetPerfmonData] TO [reporting]
GO
