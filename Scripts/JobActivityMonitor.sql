SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON
GO
--=============================================
-- Copyright (C) 2019 Raul Gonzalez, @SQLDoubleG
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
-- Create date: 04/05/2019
-- Description:	Returns information similar to the Job Activity Monitor
-- 
-- Remarks:		This script is based on the system SP [msdb].[dbo].[sp_get_composite_job_info]
--
-- Change log:	04/05/2019 RAG	- Created
--
-- =============================================
--==============================================
-- Filters
--==============================================

DECLARE @execution_status INT = NULL -- 0 = Not idle or suspended, 1 = Executing, 2 = Waiting For Thread
									-- , 3 = Between Retries, 4 = Idle, 5 = Suspended, [6 = WaitingForStepToFinish]
									-- , 7 = PerformingCompletionActions, NULL = No filter
  
--==============================================
-- Script Starts
--==============================================

DECLARE @can_see_all_running_jobs INT = 1;
DECLARE @job_owner sysname = SUSER_SNAME();

-- Step 1: Create intermediate work tables
DECLARE @job_execution_state TABLE (
	job_id UNIQUEIDENTIFIER NOT NULL
	, date_started INT NOT NULL
	, time_started INT NOT NULL
	, execution_job_status INT NOT NULL
	, execution_step_id INT NULL
	, execution_step_name sysname COLLATE DATABASE_DEFAULT NULL
	, execution_retry_attempt INT NOT NULL
	, next_run_date INT NOT NULL
	, next_run_time INT NOT NULL
	, next_run_schedule_id INT NOT NULL);

DECLARE @filtered_jobs TABLE (
	job_id UNIQUEIDENTIFIER NOT NULL
	, date_created DATETIME NOT NULL
	, date_last_modified DATETIME NOT NULL
	, current_execution_status INT NULL
	, current_execution_step NVARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
	, current_retry_attempt INT NULL
	, last_run_date INT NOT NULL
	, last_run_time INT NOT NULL
	, last_run_outcome INT NOT NULL
	, next_run_date INT NULL
	, next_run_time INT NULL
	, next_run_schedule_id INT NULL
	, type INT NOT NULL);

DECLARE @xp_results TABLE (
	job_id UNIQUEIDENTIFIER NOT NULL
	, last_run_date INT NOT NULL
	, last_run_time INT NOT NULL
	, next_run_date INT NOT NULL
	, next_run_time INT NOT NULL
	, next_run_schedule_id INT NOT NULL
	, requested_to_run INT NOT NULL -- BOOL
	, request_source INT NOT NULL
	, request_source_id sysname COLLATE DATABASE_DEFAULT NULL
	, running INT NOT NULL -- BOOL
	, current_step INT NOT NULL
	, current_retry_attempt INT NOT NULL
	, job_state INT NOT NULL);

-- Step 2: Capture job execution information (for local jobs only since that's all SQLServerAgent caches)
INSERT INTO @xp_results
	EXECUTE master.dbo.xp_sqlagent_enum_jobs
		@can_see_all_running_jobs, @job_owner;

INSERT INTO @job_execution_state
	SELECT xpr.job_id, xpr.last_run_date, xpr.last_run_time, xpr.job_state, sjs.step_id, sjs.step_name
			, xpr.current_retry_attempt, xpr.next_run_date, xpr.next_run_time, xpr.next_run_schedule_id
		FROM @xp_results AS xpr
			INNER JOIN msdb.dbo.sysjobs_view AS sjv
				ON sjv.job_id = xpr.job_id
			LEFT OUTER JOIN msdb.dbo.sysjobsteps AS sjs
				ON ((xpr.job_id = sjs.job_id) AND (xpr.current_step = sjs.step_id));

-- Optimize for the frequently used case...
INSERT INTO @filtered_jobs
	SELECT sjv.job_id
			, sjv.date_created
			, sjv.date_modified
			, ISNULL(jes.execution_job_status, 4) -- Will be NULL if the job is non-local or is not in @job_execution_state (NOTE: 4 = STATE_IDLE)
			, CASE ISNULL(jes.execution_step_id, 0)WHEN 0 THEN NULL -- Will be NULL if the job is non-local or is not in @job_execution_state
				ELSE CONVERT(NVARCHAR, jes.execution_step_id) + N' (' + jes.execution_step_name + N')'
			END
			, jes.execution_retry_attempt -- Will be NULL if the job is non-local or is not in @job_execution_state
			, 0 -- last_run_date placeholder    (we'll fix it up in step 3.3)
			, 0 -- last_run_time placeholder    (we'll fix it up in step 3.3)
			, 5 -- last_run_outcome placeholder (we'll fix it up in step 3.3 - NOTE: We use 5 just in case there are no jobservers for the job)
			, jes.next_run_date -- Will be NULL if the job is non-local or is not in @job_execution_state
			, jes.next_run_time -- Will be NULL if the job is non-local or is not in @job_execution_state
			, jes.next_run_schedule_id -- Will be NULL if the job is non-local or is not in @job_execution_state
			, 0 -- type placeholder             (we'll fix it up in step 3.4)
		FROM msdb.dbo.sysjobs_view sjv
			LEFT OUTER JOIN @job_execution_state jes
				ON (sjv.job_id = jes.job_id)		

-- Step 3.1: Change the execution status of non-local jobs from 'Idle' to 'Unknown'
UPDATE
	@filtered_jobs
SET	current_execution_status = NULL
WHERE (current_execution_status = 4)
	  AND (job_id IN (SELECT job_id FROM msdb.dbo.sysjobservers WHERE (server_id <> 0)));

-- Step 3.2: Check that if the user asked to see idle jobs that we still have some.
--           If we don't have any then the query should return no rows.
--IF (@execution_status = 4) AND
--   (NOT EXISTS (SELECT *
--                FROM @filtered_jobs
--                WHERE (current_execution_status = 4)))
--BEGIN
--  DELETE FROM @filtered_jobs
--END

-- RAG, filter by the @exection status if provided
IF (@execution_status IS NOT NULL) BEGIN
	DELETE FROM @filtered_jobs
	WHERE current_execution_status <> @execution_status;
END;

-- Step 3.3: Populate the last run date/time/outcome [this is a little tricky since for
--           multi-server jobs there are multiple last run details in sysjobservers, so
--           we simply choose the most recent].
IF (EXISTS (SELECT * FROM msdb.dbo.systargetservers)) BEGIN
	UPDATE
		@filtered_jobs
	SET
		last_run_date = sjs.last_run_date, last_run_time = sjs.last_run_time, last_run_outcome = sjs.last_run_outcome
	FROM @filtered_jobs fj, msdb.dbo.sysjobservers sjs
	WHERE (CONVERT(FLOAT, sjs.last_run_date) * 1000000) + sjs.last_run_time = (SELECT
																				   MAX((CONVERT(FLOAT, last_run_date) * 1000000) + last_run_time)
																			   FROM msdb.dbo.sysjobservers
																			   WHERE (job_id = sjs.job_id))
		  AND (fj.job_id = sjs.job_id);
END;
ELSE BEGIN
	UPDATE
		@filtered_jobs
	SET
		last_run_date = sjs.last_run_date, last_run_time = sjs.last_run_time, last_run_outcome = sjs.last_run_outcome
	FROM @filtered_jobs fj, msdb.dbo.sysjobservers sjs
	WHERE (fj.job_id = sjs.job_id);
END;

-- Step 3.4 : Set the type of the job to local (1) or multi-server (2)
--            NOTE: If the job has no jobservers then it wil have a type of 0 meaning
--                  unknown.  This is marginally inconsistent with the behaviour of
--                  defaulting the category of a new job to [Uncategorized (Local)], but
--                  prevents incompletely defined jobs from erroneously showing up as valid
--                  local jobs.
UPDATE
	@filtered_jobs
SET
	type = 1 -- LOCAL
FROM @filtered_jobs fj, msdb.dbo.sysjobservers sjs
WHERE (fj.job_id = sjs.job_id)
	  AND (server_id = 0);
UPDATE
	@filtered_jobs
SET
	type = 2 -- MULTI-SERVER
FROM @filtered_jobs fj, msdb.dbo.sysjobservers sjs
WHERE (fj.job_id = sjs.job_id)
	  AND (server_id <> 0);

-- Return the result set (NOTE: No filtering occurs here)
SELECT --sjv.job_id,
		--originating_server, 
		sjv.name
		, CASE WHEN sjv.enabled = 1 THEN 'Yes' ELSE 'No' END AS [enabled]
		, CASE ISNULL(fj.current_execution_status, 0)WHEN 0 THEN 'Not idle or suspended'
		WHEN 1 THEN 'Executing (Step:' + ISNULL(fj.current_execution_step, N'0 ' + FORMATMESSAGE(14205)) + ')'
		WHEN 2 THEN 'Waiting For Thread'
		WHEN 3 THEN 'Between Retries'
		WHEN 4 THEN 'Idle'
		WHEN 5 THEN 'Suspended'
		WHEN 6 THEN 'WaitingForStepToFinish'
		WHEN 7 THEN 'PerformingCompletionActions'
		END AS current_execution_status
		, CASE WHEN fj.last_run_date = 0 THEN 'never'
		ELSE CONVERT(VARCHAR, CONVERT(DATE, CONVERT(VARCHAR, fj.last_run_date)), 103) + ' @ ' + +LEFT(RIGHT('000000' + CONVERT(VARCHAR, fj.last_run_time), 6), 2) + ':' + SUBSTRING(RIGHT('000000' + CONVERT(VARCHAR, fj.last_run_time), 6), 3, 2) + ':' + RIGHT(RIGHT('000000' + CONVERT(VARCHAR, fj.last_run_time), 6), 2)
		END AS last_run_date
		--fj.last_run_time,
		, CASE fj.last_run_outcome WHEN 0 THEN 'Fail'
		WHEN 1 THEN 'Succeed'
		WHEN 3 THEN 'Cancel'
		ELSE 'Unknown'
		END AS last_run_outcome
		, CASE WHEN ISNULL(fj.next_run_date, 0) = 0 THEN 'not scheduled'
		ELSE CONVERT(VARCHAR, CONVERT(DATE, CONVERT(VARCHAR, fj.next_run_date)), 103) + ' @ ' + +LEFT(RIGHT('000000' + CONVERT(VARCHAR, fj.next_run_time), 6), 2) + ':' + SUBSTRING(RIGHT('000000' + CONVERT(VARCHAR, fj.next_run_time), 6), 3, 2) + ':' + RIGHT(RIGHT('000000' + CONVERT(VARCHAR, fj.next_run_time), 6), 2)
		END AS next_run_date

		, current_retry_attempt = ISNULL(fj.current_retry_attempt, 0) -- This column will be NULL if the job is non-local
		, category = ISNULL(sc.name, FORMATMESSAGE(14205))		
		, sjv.description
		--sjv.start_step_id,
		--owner = dbo.SQLAGENT_SUSER_SNAME(sjv.owner_sid),
		--sjv.notify_level_eventlog,
		--sjv.notify_level_email,
		--sjv.notify_level_netsend,
		--sjv.notify_level_page,
		--notify_email_operator   = ISNULL(so1.name, FORMATMESSAGE(14205)),
		--notify_netsend_operator = ISNULL(so2.name, FORMATMESSAGE(14205)),
		--notify_page_operator    = ISNULL(so3.name, FORMATMESSAGE(14205)),
		--sjv.delete_level,
		--sjv.date_created,
		--sjv.date_modified,
		--sjv.version_number,
		--has_step = (SELECT COUNT(*)
		--            FROM msdb.dbo.sysjobsteps sjst
		--            WHERE (sjst.job_id = sjv.job_id)),
		--has_schedule = (SELECT COUNT(*)
		--                FROM msdb.dbo.sysjobschedules sjsch
		--                WHERE (sjsch.job_id = sjv.job_id)),
		--has_target = (SELECT COUNT(*)
		--              FROM msdb.dbo.sysjobservers sjs
		--              WHERE (sjs.job_id = sjv.job_id)),
		--type = fj.type
	FROM @filtered_jobs fj
		LEFT OUTER JOIN msdb.dbo.sysjobs_view sjv
			ON (fj.job_id = sjv.job_id)
		LEFT OUTER JOIN msdb.dbo.syscategories sc  ON (sjv.category_id = sc.category_id)
		--LEFT OUTER JOIN msdb.dbo.sysoperators  so1 ON (sjv.notify_email_operator_id = so1.id)
		--LEFT OUTER JOIN msdb.dbo.sysoperators  so2 ON (sjv.notify_netsend_operator_id = so2.id)
		--LEFT OUTER JOIN msdb.dbo.sysoperators  so3 ON (sjv.notify_page_operator_id = so3.id)
	ORDER BY sjv.[enabled] DESC, fj.current_execution_status, sjv.name;

GO
