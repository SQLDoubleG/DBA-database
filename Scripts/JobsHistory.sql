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
--				29/04/2015 RAG - Added Parameter @includeSteps to display info for each step of a job
--				07/05/2015 RAG - Added Parameters @jobName and @includeLastNexecutions to filter by name and display some history
--				13/04/2016 SZO - Added element to ORDER BY clause so results returned by step_id with result step (step 0) returned last.
--				21/04/2016 SZO - Modified ORDER BY clause so results display as shown in SQL Agent View History Window.
--				22/04/2016 RAG - Renamed to [dbo].[DBA_jobsHistory] as [dbo].[DBA_jobsDescription] now will show only information about jobs, not history
--				30/06/2016 RAG - Added column server_name and EXECUTE AS 'dbo' due to this SP will be called by dbaMonitoringUser
--				30/09/2018 RAG - Created new Dependencies section
--								- Added dependant function as tempdb object 
--				20/10/2018 RAG - Added column [job_id_binary] to help locate output files when they user the token $(JOBID)
--				22/11/2018 RAG 	- Added columns jobsteps.subsystem and jobsteps.command
--								- Added parameter @commandText to filter the job step command text
--				21/02/2019 RAG 	- Fixed multiple rows per job due to adding steps
--				15/03/2019 RAG 	- Added active_start_time and active_time for schedules
--								- Other fixes 
--				19/03/2019 RAG 	- Changed to FULL OUTER JOIN from jobhistory to jobsteps as there is Step 0 in jobhistory that does not exist as such
--								- Changed column [schedules] to concatenate multiple schedules with [AND] as multiple schedules returned multiple rows
--				20/03/2019 RAG 	- Added ISNULL for null columns when there is no history for a job
--								- Added column last_run_duration
--								- Removed comments
--				28/03/2019 RAG 	- Split the logic if we want to get steps or not
--								- Fixed bug when a job didn't execute all the steps
--								- Added case statement for run_status
--								- Change the order of the final output columns
--				01/04/2019 RAG 	- Changes in how the schedules are displayed
--				23/05/2019 RAG 	- Added scape character for the job names
--				02/07/2019 RAG 	- Changed the scape character from \ to ` as \ is more commonly used in job names
--								- Changed ISNULL() for @param IS NULL OR 
--								- Added @errMessage filter 
--				03/08/2019 RAG 	- Changed the order of the LEFT JOIN to get job steps when there is no history
--								- Added columns [start_step_id], [on_success_action] and [on_failure_action] to the final output
--								- Always insert Step 0 (Job Outcome) and the rest only if @includeSteps = 1
--									but only display it when the job has run at least once
--				22/10/2019 RAG 	- Added database_name for each step
--				08/12/2019 RAG 	- Fixed a bug that didn't return correct step information which made sorting incorrect
--				13/10/2020 RAG 	- Added output_file_name column
--
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
IF OBJECT_ID('tempdb..#monthlyRelative')	IS NOT NULL DROP TABLE #monthlyRelative

CREATE TABLE #monthlyRelative (ID TINYINT NOT NULL, Name VARCHAR(15) NOT NULL)
INSERT INTO #monthlyRelative
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
GO
-- =============================================
-- END of Dependencies
-- =============================================
DECLARE	@onlyActiveJobs				BIT = 1
		, @includeSteps				BIT = 0
		, @jobName					SYSNAME 
		, @commandText				SYSNAME 
		, @errMessage				NVARCHAR(MAX)
		, @includeLastNexecutions	INT = 1
	
SET NOCOUNT ON

IF ISNULL(@commandText, '') <> '' SET @includeSteps = 1
IF ISNULL(@errMessage, '') <> '' SET @includeSteps = 1

SET @includeLastNexecutions = ISNULL(@includeLastNexecutions, 1)

IF OBJECT_ID('tempdb..#jobHistory')		IS NOT NULL DROP TABLE #jobHistory
IF OBJECT_ID('tempdb..#jobs')			IS NOT NULL DROP TABLE #jobs
IF OBJECT_ID('tempdb..#Step1')			IS NOT NULL DROP TABLE #Step1

CREATE TABLE #jobHistory(
	job_name				SYSNAME
	, job_id				UNIQUEIDENTIFIER	
	, instance_id			INT					NULL
	, step_id				INT					NULL
	, step_name				SYSNAME				NULL
	, database_name			SYSNAME				NULL
	, run_date				INT					NULL
	, run_status			INT					NULL
	, run_time				INT					NULL
	, run_duration			INT					NULL
	, on_success_action		TINYINT				NULL
	, on_success_step_id	INT					NULL
	, on_fail_action		TINYINT				NULL
	, on_fail_step_id		INT					NULL
	, subsystem				NVARCHAR(40)		NULL
	, command				NVARCHAR(MAX)		NULL
	, output_file_name		NVARCHAR(200)		NULL
	, message				NVARCHAR(MAX)		NULL)

--Get all jobs we're interested
SELECT j.job_id
		, j.name 
		, j.enabled
		, j.start_step_id
	INTO #jobs
	FROM msdb.dbo.sysjobs AS j
	WHERE (( @onlyActiveJobs = 1 AND j.enabled = 1 ) OR @onlyActiveJobs = 0)
		AND j.name LIKE ISNULL(@jobName, REPLACE(REPLACE(j.name, '[', '`['), ']', '`]')) ESCAPE '`'
	ORDER BY j.name


	-- this is the job output if any history
	;WITH cte AS(
	SELECT 	j.name AS job_name
			, j.job_id
			, jh.instance_id
			, jh.step_id
			, jh.step_name
			, NULL AS database_name
			, jh.run_date
			, jh.run_status
			, jh.run_time
			, jh.run_duration
			, '-' AS on_success_action	
			, '-' AS on_success_step_id
			, '-' AS on_fail_action	
			, '-' AS on_fail_step_id	
			, '-' AS subsystem
			, '-' AS command
			, '-' AS output_file_name
			, '-' AS message
			, ROW_NUMBER() OVER (PARTITION BY j.job_id, jh.step_id ORDER BY jh.run_date DESC, jh.run_time DESC) AS rowNumber		
		FROM #jobs AS j
			INNER JOIN msdb.dbo.sysjobhistory AS jh
				ON jh.job_id = j.job_id
					AND jh.step_id = 0
	)
	INSERT INTO #jobHistory
		SELECT cte.job_name
				, cte.job_id
				, cte.instance_id
				, cte.step_id
				, cte.step_name
				, cte.database_name
				, cte.run_date
				, cte.run_status
				, cte.run_time
				, cte.run_duration
				, cte.on_success_action	
				, cte.on_success_step_id
				, cte.on_fail_action	
				, cte.on_fail_step_id	
				, cte.subsystem
				, cte.command 
				, cte.output_file_name 
				, cte.message
			FROM cte
			WHERE cte.rowNumber <= @includeLastNexecutions 

IF @includeSteps = 1 BEGIN
	
	-- this is the first step for each run if any history
	SELECT 	j.job_id
		, jh.instance_id
		, ROW_NUMBER() OVER (PARTITION BY jh.job_id, jh.step_id ORDER BY jh.run_date DESC, jh.run_time DESC) AS rowNumber		
	INTO #Step1
	FROM #jobs AS j
		LEFT JOIN msdb.dbo.sysjobhistory AS jh
			ON jh.job_id = j.job_id
				AND jh.step_id = 1

	DELETE FROM #Step1 WHERE rowNumber > @includeLastNexecutions
	
	INSERT INTO #jobHistory
	SELECT j.name AS job_name
			, j.job_id
			, jh.instance_id
			, ISNULL(js.step_id, jh.step_id) AS step_id
			, ISNULL(js.step_name, jh.step_name) AS step_name
			, js.database_name
			, jh.run_date
			, jh.run_status
			, jh.run_time
			, jh.run_duration
			, js.on_success_action	
			, js.on_success_step_id
			, js.on_fail_action	
			, js.on_fail_step_id	
			, ISNULL(js.subsystem, '-') AS subsystem
			, ISNULL(js.command, '-') AS command
			, ISNULL(js.output_file_name, '-') AS output_file_name
			, ISNULL(jh.message, '-') AS message
		FROM 
		(
		SELECT j.job_id, j.name, h.instance_id 
			FROM #jobs AS j
			OUTER APPLY (SELECT job_id, instance_id 
							FROM #Step1 
							WHERE job_id = j.job_id 
								AND rowNumber <= @includeLastNexecutions) AS h
		) AS j

		INNER  JOIN msdb.dbo.sysjobsteps AS js
			ON js.job_id = j.job_id
		CROSS APPLY (SELECT TOP 1 jh.*
						FROM msdb.dbo.sysjobhistory AS jh
							WHERE jh.job_id = j.job_id
								AND jh.step_id = js.step_id
								AND jh.instance_id >= j.instance_id
					ORDER BY jh.instance_id) AS jh
		WHERE (@commandText IS NULL OR js.command LIKE @commandText) 
			AND (@errMessage IS NULL OR jh.message LIKE @errMessage)
		ORDER BY j.job_id, jh.instance_id DESC

END

-- Get final results
SELECT  @@SERVERNAME AS server_name
		, j.job_id
		, CONVERT(VARBINARY(85), j.job_id) AS job_id_binary
		, j.name AS job_name
		, CASE WHEN j.enabled = 1 THEN 'Yes' ELSE 'No' END AS [enabled]
		, j.start_step_id
		, ISNULL(CONVERT(VARCHAR(30), jh.step_id), '-')   AS step_id
		, ISNULL(jh.step_name, '-')	AS step_name
		, ISNULL(jh.database_name, '-')	AS database_name
		, CASE WHEN jh.run_date <> 0 THEN 
			(CONVERT(VARCHAR, CONVERT(DATE, 
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 1,4)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 5,2)		+ '-' +
					SUBSTRING(CONVERT(VARCHAR(8),jh.run_date), 7,2))))	+ ' ' +
				[tempdb].[dbo].[formatMStimeToHR](jh.run_time)
			ELSE '-'
		END AS last_run
		, [tempdb].[dbo].[formatMStimeToHR](jh.run_duration) AS last_run_duration
		, CASE jh.run_status
			WHEN 0 THEN 'Failed'
			WHEN 1 THEN 'Succeeded'
			WHEN 2 THEN 'Retry'
			WHEN 3 THEN 'Canceled'
			WHEN 4 THEN 'In Progress'
			ELSE '-'
		END AS run_status
		, ISNULL(
			STUFF(
				(SELECT ' [AND] ' + 
						CASE 
							WHEN s.freq_type = 1	THEN 'Once on '	
									+ CONVERT(VARCHAR(20), CONVERT(DATE, CONVERT(VARCHAR, s.active_start_date)), 103) 
									+ ' @ ' + [tempdb].[dbo].[formatMStimeToHR](s.active_start_time)
							WHEN s.freq_type = 4	THEN 'Every' + CASE WHEN s.freq_interval > 1 THEN ' ' ELSE '' END + ISNULL(NULLIF(CONVERT(VARCHAR, s.freq_interval),1),'') + ' Day' + CASE WHEN s.freq_interval > 1 THEN 's' ELSE '' END
							WHEN s.freq_type = 8	THEN -- Weekly
															ISNULL( STUFF( (SELECT N', ' + B.name 
																				FROM #DaysOfWeekBitWise AS B 
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
															+ (SELECT Name FROM #monthlyRelative WHERE ID = s.freq_interval) + ' of the month'
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
						END + 
						CASE WHEN s.freq_subday_type NOT IN (4, 8) THEN ''
							--WHEN 4 THEN ''
							ELSE ', From ' + [tempdb].[dbo].[formatMStimeToHR](s.active_start_time) + ' till ' + [tempdb].[dbo].[formatMStimeToHR](s.active_end_time)			
						END + 
						CASE WHEN s.enabled = 1 THEN ''
							ELSE + ' (Disabled)'
						END
					FROM msdb.dbo.sysjobschedules AS jsch
						INNER JOIN msdb.dbo.sysschedules AS s
							ON s.schedule_id = jsch.schedule_id
					WHERE jsch.job_id = j.job_id
					FOR XML PATH('')), 1, 7, ''), '-') AS schedules
		, ISNULL(jh.subsystem, '-')   AS subsystem
		, ISNULL(jh.command, '-')	AS command
		, ISNULL(jh.output_file_name, '-')	AS output_file_name		
		, ISNULL(jh.message, '-')	AS message
		, CASE jh.on_success_action	
			WHEN 1 THEN 'Quit the job reporting success'
			WHEN 2 THEN 'Quit the job reporting failure'
			WHEN 3 THEN 'Go to the next step'
			WHEN 4 THEN 'Go to step ' + CONVERT(VARCHAR(30), jh.on_success_step_id)
			ELSE '-'
		END AS on_success_action	
		--, jh.on_success_step_id
		, CASE jh.on_fail_action	
			WHEN 1 THEN 'Quit the job reporting success'
			WHEN 2 THEN 'Quit the job reporting failure'
			WHEN 3 THEN 'Go to the next step'
			WHEN 4 THEN 'Go to step ' + CONVERT(VARCHAR(30), jh.on_success_step_id)
			ELSE '-'
		END AS on_fail_action
		--, jh.on_fail_step_id	 
	FROM #jobs AS j
		LEFT JOIN #jobHistory AS jh
			ON jh.job_id = j.job_id
	WHERE (@commandText IS NULL OR jh.command LIKE @commandText) 
		AND (@errMessage IS NULL OR jh.message LIKE @errMessage)

	ORDER BY job_name, jh.instance_id DESC, step_id DESC
	
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
DROP TABLE #DaysOfWeekBitWise
GO
DROP TABLE #monthlyRelative
GO
