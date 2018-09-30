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
-- Create date: 02/07/2013
-- Description:	Returns Jobs Defined for the Server and their schedules
--
--	Values taken from 
--	http://msdn.microsoft.com/en-us/library/ms178644.aspx
--
-- Dependencies: Bit values for the days of the week are taken from [DBA].[dbo].[DaysOfWeekBitWise]
--					Duration is calculated using the function [DBA].[dbo].[formatMStimeToHR]
--
-- Permissions:
--				GRANT EXECUTE ON [DBA].[dbo].[DBA_jobsHistory] TO [dbaMonitoringUser]
-- 
-- Log History:	
--				29/04/2015 RAG -- Added Parameter @includeSteps to display info for each step of a job
--				07/05/2015 RAG -- Added Parameters @jobName and @includeLastNexecutions to filter by name and display some history
--				13/04/2016 SZO -- Added element to ORDER BY clause so results returned by step_id with result step (step 0) returned last.
--				21/04/2016 SZO -- Modified ORDER BY clause so results display as shown in SQL Agent View History Window.
--				22/04/2016 RAG -- Renamed to [dbo].[DBA_jobsHistory] as [dbo].[DBA_jobsDescription] now will show only information about jobs, not history
--				30/06/2016 RAG -- Added column server_name and EXECUTE AS 'dbo' due to this SP will be called by dbaMonitoringUser
--				30/09/2018 RAG Created new Dependencies section
--								- Added dependant function as tempdb object 

-- =============================================
-- =============================================
-- Dependencies:This Section will create on tempdb any dependancy
-- =============================================
USE tempdb
GO
CREATE FUNCTION [dbo].[formatMStimeToHR](
	@duration INT
)
RETURNS VARCHAR(24)
AS
BEGIN
	-- Declare the return variable here
	DECLARE @strDuration VARCHAR(24)
	DECLARE @R			VARCHAR(24)

	SET @strDuration = RIGHT(REPLICATE('0',24) + CONVERT(VARCHAR(24),@duration), 24)

	SET @R = ISNULL(NULLIF(CONVERT(VARCHAR	, CONVERT(INT,SUBSTRING(@strDuration, 1, 20)) / 24 ),0) + '.', '') + 
				RIGHT('00' + CONVERT(VARCHAR, CONVERT(INT,SUBSTRING(@strDuration, 1, 20)) % 24 ), 2) + ':' + 
				SUBSTRING( @strDuration, 21, 2) + ':' + 
				SUBSTRING( @strDuration, 23, 2)
	
	RETURN ISNULL(@R,'-')

END
GO
IF OBJECT_ID('tempdb..#DaysOfWeekBitWise') IS NOT NULL DROP TABLE #DaysOfWeekBitWise
GO
CREATE TABLE #DaysOfWeekBitWise(
	[bitValue] [tinyint] NOT NULL,
	[name] [varchar] (10) COLLATE Latin1_General_CI_AS NULL,
	[DayNumberOfTheWeek] [tinyint] NULL
)
INSERT INTO #DaysOfWeekBitWise VALUES
(1, 'Sunday', 7)
, (2, 'Monday', 1)
, (4, 'Tuesday', 2)
, (8, 'Wednesday', 3)
, (16, 'Thursday', 4)
, (32, 'Friday', 5)
, (64, 'Saturday', 6)
GO
-- =============================================
-- END of Dependencies
-- =============================================
DECLARE	@onlyActiveJobs				BIT = 0
		, @includeSteps				BIT = 0
		, @jobName					SYSNAME = NULL
		, @includeLastNexecutions	INT = 1
	
SET NOCOUNT ON

IF OBJECT_ID('tempdb..#jobHistory') IS NOT NULL DROP TABLE #jobHistory
IF OBJECT_ID('tempdb..#jobs')		IS NOT NULL DROP TABLE #jobs

DECLARE @monthlyRelative TABLE (ID TINYINT NOT NULL, Name VARCHAR(15) NOT NULL)
INSERT INTO @monthlyRelative
	VALUES (1, 'Sunday')
			, (2, 'Monday')
			, (3, 'Tuesday')
			, (4, 'Wednesday')
			, (5, 'Thursday')
			, (6, 'Friday')
			, (7, 'Saturday')
			, (8, 'Day')
			, (9, 'Weekday')
			, (10, 'Weekend day')

--Get all jobs we're interested
SELECT * 
	INTO #jobs
	FROM msdb.dbo.sysjobs AS j
	WHERE (( @onlyActiveJobs = 1 AND j.enabled = 1 ) OR @onlyActiveJobs = 0)
		AND j.name LIKE ISNULL(@jobName, j.name)
		
-- Take from history, the last run for each job
;WITH CTE AS(
	SELECT jh.*
			, ROW_NUMBER() OVER (PARTITION BY jh.job_id, jh.step_id ORDER BY jh.run_date DESC, run_time DESC) AS rowNumber		
		FROM msdb.dbo.sysjobhistory AS jh
			INNER JOIN #jobs AS j
				ON j.job_id = jh.job_id
		WHERE step_id = 0 OR @includeSteps = 1
	)
	SELECT * 
		INTO #jobHistory
		FROM CTE
	WHERE rowNumber <= @includeLastNexecutions
		
-- Get final results
SELECT  @@SERVERNAME AS server_name
		, j.job_id
		, j.name AS job_name
		, jh.step_id
		, jh.step_name
		, CASE WHEN j.enabled = 1 THEN 'Yes' ELSE 'No' END AS [enabled]
		, SUSER_SNAME(j.owner_sid) as owner_name
		, CASE 
			WHEN s.freq_type = 1	THEN 'Once'					
			WHEN s.freq_type = 4	THEN 'Every' + CASE WHEN s.freq_interval > 1 THEN ' ' ELSE '' END + ISNULL(NULLIF(CONVERT(VARCHAR, s.freq_interval),1),'') + ' Day' + CASE WHEN s.freq_interval > 1 THEN 's' ELSE '' END
			WHEN s.freq_type = 8	THEN -- Weekly
											ISNULL( STUFF( (SELECT N', ' + name 
																FROM DBA.dbo.DaysOfWeekBitWise AS B 
																WHERE B.bitValue & s.freq_interval = B.bitValue 
																	AND s.freq_type = 8
																FOR XML PATH('') ), 1, 2, '' ), 'None' )
			WHEN s.freq_type = 16	THEN 'Every ' + CONVERT(VARCHAR, s.freq_interval) + ' of the month'
			WHEN s.freq_type = 32	THEN 
											CASE 
												WHEN s.freq_relative_interval = 1	THEN 'First ' 
												WHEN s.freq_relative_interval = 2	THEN 'Second ' 
												WHEN s.freq_relative_interval = 4	THEN 'Third ' 
												WHEN s.freq_relative_interval = 8	THEN 'Fourth ' 
												WHEN s.freq_relative_interval = 16	THEN 'Last ' 
											END
											+ (SELECT Name FROM @monthlyRelative WHERE ID = s.freq_interval) + ' of the month'
			WHEN s.freq_type = 64	THEN 'Starts when SQL Server Agent service starts'
			WHEN s.freq_type = 128	THEN 'Runs when computer is idle'
			ELSE 'None'
		END 
		+ 
		CASE s.freq_subday_type 
			WHEN 1 THEN ' @ ' + 
				SUBSTRING( RIGHT('000000' + CONVERT(VARCHAR(6),s.active_start_time), 6), 1, 2) + ':' + 
				SUBSTRING( RIGHT('000000' + CONVERT(VARCHAR(6),s.active_start_time), 6), 3, 2) + ':' + 
				SUBSTRING( RIGHT('000000' + CONVERT(VARCHAR(6),s.active_start_time), 6), 5, 2) 
			WHEN 2 THEN '. Every ' + CONVERT(VARCHAR,s.freq_subday_interval) + ' second'	+ CASE WHEN s.freq_subday_interval > 1 THEN 's' ELSE '' END
			WHEN 4 THEN '. Every ' + CONVERT(VARCHAR,s.freq_subday_interval) + ' minute'	+ CASE WHEN s.freq_subday_interval > 1 THEN 's' ELSE '' END
			WHEN 8 THEN '. Every ' + CONVERT(VARCHAR,s.freq_subday_interval) + ' hour'		+ CASE WHEN s.freq_subday_interval > 1 THEN 's' ELSE '' END
			ELSE ''
		END AS job_schedule
		, CASE WHEN jsch.next_run_date <> 0 THEN 
			(CONVERT(VARCHAR, CONVERT(DATE, 
					SUBSTRING(CONVERT(VARCHAR(8),jsch.next_run_date), 1,4)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jsch.next_run_date), 5,2)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jsch.next_run_date), 7,2))))	+ ' ' +
				tempdb.dbo.formatMStimeToHR(jsch.next_run_time)
			ELSE '-'
		END AS next_run
		, CASE WHEN jh.run_date <> 0 THEN 
			(CONVERT(VARCHAR, CONVERT(DATE, 
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 1,4)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 5,2)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 7,2))))	+ ' ' +
				tempdb.dbo.formatMStimeToHR(jh.run_time)
			ELSE '-'
		END AS last_run
		, CASE 
			WHEN jh.run_status IS NULL THEN '-'
			WHEN jh.run_status = 0 THEN 'Failed'
			WHEN jh.run_status = 1 THEN 'Succeeded'
			WHEN jh.run_status = 2 THEN 'Retry'
			WHEN jh.run_status = 3 THEN 'Canceled'
		END AS last_run_status
		, tempdb.dbo.formatMStimeToHR (jh.run_duration) AS last_run_duration
	FROM #jobs AS j
		LEFT JOIN msdb.dbo.sysjobschedules AS jsch
			ON jsch.job_id = j.job_id
		LEFT JOIN msdb.dbo.sysschedules AS s
			ON s.schedule_id = jsch.schedule_id
		LEFT JOIN #jobHistory AS jh
			ON jh.job_id = j.job_id
	ORDER BY job_name, jh.rowNumber, CASE WHEN jh.step_id = 0 THEN POWER(2, 30) ELSE jh.step_id END DESC, jh.instance_id DESC
	
DROP TABLE #jobHistory
DROP TABLE #jobs
OnError:
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[formatMStimeToHR]
GO