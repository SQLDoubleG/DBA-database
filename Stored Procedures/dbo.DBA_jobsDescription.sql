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
-- Log History:	
--				29/04/2015 RAG -- Added Parameter @includeSteps to display info for each step of a job
--				07/05/2015 RAG -- Added Parameters @jobName and @includeLastNexecutions to filter by name and display some history
--				13/04/2016 SZO -- Added element to ORDER BY clause so results returned by step_id with result step (step 0) returned last.
--				21/04/2016 SZO -- Modified ORDER BY clause so results display as shown in SQL Agent View History Window.
--				22/04/2016 RAG -- Removed all related to history information as there is a new sp [dbo].[DBA_jobsHistory] which does that
--									Columns are now
--										- job_name	
--										- enabled	
--										- owner_name	
--										- Category	
--										- description	
--										- job_schedule	
--										- next_run	
--										- Start step	
--										- Actions to perform when the job completes	
--										- Autodelete	
--										- step_id	step_name	
--										- database_name	
--										- Type	
--										- command	
--										- On Success	
--										- On Failure	
--										- Run As	
--										- Output file	
--										- job_id
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_jobsDescription]
	@onlyActiveJobs				BIT = 0
	, @includeSteps				BIT = 0
	, @jobName					SYSNAME = NULL
AS
BEGIN
	
	SET NOCOUNT ON

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
	SELECT 
			 j.name AS job_name
			, CASE WHEN j.enabled = 1 THEN 'Yes' ELSE 'No' END AS [enabled]
			, SUSER_SNAME(j.owner_sid) as owner_name
			, c.name AS [Category]
			, j.description
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
					dbo.formatMStimeToHR(jsch.next_run_time)
				ELSE '-'
			END AS next_run

			, 'Start Step: [' + CONVERT(VARCHAR, j.start_step_id) + ']' AS [Start step]

			,	ISNULL(
				'Email: ' + QUOTENAME(email_op.name) + 
				CASE notify_level_email 
					WHEN 0 THEN NULL
					WHEN 1 THEN ' When the job succeeds'
					WHEN 2 THEN ' When the job fails'
					WHEN 3 THEN ' When the job completes'
				END + ';', '')
				+ 
				ISNULL(
				'Page: ' + QUOTENAME(page_op.name) + 
				CASE notify_level_page
					WHEN 0 THEN NULL
					WHEN 1 THEN 'When the job succeeds'
					WHEN 2 THEN 'When the job fails'
					WHEN 3 THEN 'When the job completes'
				END + ';', '')
				+ 
				ISNULL(
				'Net send: ' + QUOTENAME(netsent_op.name) + 
				CASE notify_level_netsend
					WHEN 0 THEN NULL
					WHEN 1 THEN 'When the job succeeds'
					WHEN 2 THEN 'When the job fails'
					WHEN 3 THEN 'When the job completes'
				END + ';', '')
				+ 
				ISNULL(
				'Write to the Windows Application event log: ' + QUOTENAME(netsent_op.name) + 
				CASE notify_level_eventlog
					WHEN 0 THEN NULL
					WHEN 1 THEN 'When the job succeeds'
					WHEN 2 THEN 'When the job fails'
					WHEN 3 THEN 'When the job completes'
				END + ';', '')
				AS [Actions to perform when the job completes]
				, 
				ISNULL(
				'Automatically delete job: ' + 
				CASE j.delete_level
					WHEN 0 THEN NULL
					WHEN 1 THEN 'When the job succeeds'
					WHEN 2 THEN 'When the job fails'
					WHEN 3 THEN 'When the job completes'
				END, '') AS Autodelete

			, jst.step_id
			, jst.step_name
			, jst.database_name
			, jst.subsystem AS [Type]
			, jst.command
			,	CASE jst.on_success_action
					WHEN 1 THEN 'Quit the job reporting success'
					WHEN 2 THEN 'Quit the job reporting failure'
					WHEN 3 THEN 'Go to the next step'
					WHEN 4 THEN 'Go to the step [' + CONVERT(VARCHAR, jst.on_success_step_id) + ']'
				END AS [On Success]

			,	CASE jst.on_fail_action
					WHEN 1 THEN 'Quit the job reporting success'
					WHEN 2 THEN 'Quit the job reporting failure'
					WHEN 3 THEN 'Go to the next step'
					WHEN 4 THEN 'Go to the step [' + CONVERT(VARCHAR, jst.on_fail_step_id) + ']'
				END AS [On Failure]

			, ISNULL(prx.name, '') AS [Run As]
			, ISNULL(jst.output_file_name, '') AS [Output file]

			, j.job_id
		
		FROM msdb.dbo.sysjobs AS j
			LEFT JOIN msdb.dbo.syscategories AS c
				ON c.category_id = j.category_id
			LEFT JOIN msdb.dbo.sysjobsteps AS jst
				ON jst.job_id = j.job_id
					AND @includeSteps = 1
			LEFT JOIN msdb.dbo.sysproxies AS prx
				ON prx.proxy_id = jst.proxy_id
			LEFT JOIN msdb.dbo.sysjobschedules AS jsch
				ON jsch.job_id = j.job_id
			LEFT JOIN msdb.dbo.sysschedules AS s
				ON s.schedule_id = jsch.schedule_id

			LEFT JOIN msdb.dbo.sysoperators AS email_op
				ON email_op.id = j.notify_email_operator_id
			LEFT JOIN msdb.dbo.sysoperators AS page_op
				ON email_op.id = j.notify_page_operator_id
			LEFT JOIN msdb.dbo.sysoperators AS netsent_op
				ON email_op.id = j.notify_netsend_operator_id

		WHERE (( @onlyActiveJobs = 1 AND j.enabled = 1 ) OR @onlyActiveJobs = 0)
			AND j.name LIKE ISNULL(@jobName, j.name)
		ORDER BY job_name, jst.step_id
	
END




GO
