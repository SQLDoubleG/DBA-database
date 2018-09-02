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
-- Author:		RAG
-- Create date: 30/06/2016
-- Description:	Process the database maintenance job last execution collected in [dbo].[LastJobExecutionStatus]
--
-- Log:
--				30/06/2016	RAG	Created
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessJobLastExecution] 
AS
BEGIN

	SET NOCOUNT ON

	IF NOT EXISTS (SELECT * FROM dbo.LastJobExecutionStatus) BEGIN
		RAISERROR ('The table [dbo].[LastJobExecutionStatus] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	DECLARE @tableHTML		NVARCHAR(MAX) ;
	DECLARE @emailSubject	NVARCHAR(128) = 'Database Maintenance Job Last Execution'

	SET @tableHTML =	N'<html><head><style type="text/css">.ac {text-align:center}.diff {background-color:#FFC7CE} th{background-color:#5B9BD5;color:white;font-weight:bold} td{white-space: nowrap}</style></head><body>' +
						N'<table border="1">' +
						N'<tr class="ac"><th>server_name</th>' +
						--N'<th>job_id</th>' +
						N'<th>job_name</th>' +
						N'<th>step_id</th>' +
						N'<th>step_name</th>' +
						N'<th>enabled</th>' +
						N'<th>owner_name</th>' +
						N'<th>job_schedule</th>' +
						N'<th>next_run</th>' +
						N'<th>last_run</th>' +
						N'<th>last_run_status</th>' +
						N'<th>last_run_duration</th>' +
						N'<th>DateCollectionTime</th></tr>'

	;WITH cte AS (

		SELECT	TOP 1000000
				s.server_name,
				j.last_run_status,
				'<td>' + ISNULL(CONVERT(SYSNAME, s.server_name			), '') + '</td>' +
				--'<td>' + ISNULL(CONVERT(SYSNAME, j.job_id				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.job_name				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.step_id				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.step_name			), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.enabled				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.owner_name			), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.job_schedule			), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.next_run				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.last_run				), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.last_run_status		), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.last_run_duration	), '') + '</td>' +
				'<td>' + ISNULL(CONVERT(SYSNAME, j.DataCollectionTime	), '') + '</td>' AS HTMLRow
			FROM dbo.ServerList AS s
				LEFT JOIN [dbo].[LastJobExecutionStatus] AS j
					ON j.server_name = s.server_name
			WHERE s.isSQLServer = 1
				AND s.MonitoringActive = 1
	)
	SELECT @tableHTML += ( SELECT '<tr' +  CASE WHEN ISNULL(last_run_status, '-') IN ('-', 'Failed') THEN ' class="diff"' ELSE '' END + '>' + HTMLRow + '</tr>'
							FROM cte						
							ORDER BY cte.last_run_status, cte.server_name 
							FOR XML PATH(''), TYPE ).value('.', 'NVARCHAR(MAX)') + '</table></body></html>'

	--SELECT @tableHTML

	IF @tableHTML IS NOT NULL BEGIN	
		
		EXEC msdb.dbo.sp_send_dbmail 
			@profile_name = 'Admin Profile', 
			@recipients = 'DatabaseAdministrators@rws.com', 
			@subject = @emailSubject,
			@body = @tableHTML,  
			@body_format = 'HTML'

	END

END
GO
