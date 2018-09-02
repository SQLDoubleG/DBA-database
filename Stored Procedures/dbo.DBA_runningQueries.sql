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
-- Create date: 25/04/2013
-- Description:	Returns running queries
--
-- Parameters:
--				@sspid, a value > 0 will return only the given session_id, otherwise will return all session excluding the given one
--
-- Log History:	
--				10/08/2015 RAG	Added SUBSTRING for SQLTEXT to show only the portion being executed
--									Added the resource description to the [wait_type] column
--								Added TOP (@n) and OPTION (OPTIMIZE FOR (@n=1)) to minimize the use of memory
--				20/05/2016 RAG	Added host_name
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_runningQueries]
	@sspid	int = NULL
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @n INT = 2147483647

	SELECT TOP (@n)
			r.session_id
			, SUBSTRING(sqltext.text,
						CASE WHEN r.statement_start_offset	> 0 THEN ((r.statement_start_offset/2) + 1)	ELSE 0			END,
						CASE WHEN r.statement_end_offset	> 0 THEN ((r.statement_end_offset/2))		ELSE 2147483647 END) AS SQLTEXT
			--, sqltext.text			
			--, r.statement_start_offset
			--, r.statement_end_offset
			, DB_NAME(r.database_id) as database_Name
			, s.login_name
			, r.status
			, r.command
			, r.wait_type + CASE WHEN ISNULL(r.wait_resource, '') <> '' THEN ' (' + r.wait_resource + ')' ELSE '' END AS wait_type
			, r.start_time
			, r.percent_complete
			, case	when r.percent_complete = 0 THEN NULL
					else DATEADD (ss,DATEDIFF (ss,r.start_time,getdate()) / r.percent_complete * 100, r.start_time) 
				end AS Expected_end_time 
			, r.cpu_time
			, r.total_elapsed_time
			, r.granted_query_memory
			, r.blocking_session_id
			, SUBSTRING(blocking_sqltext.text,
						CASE WHEN br.statement_start_offset > 0 THEN ((br.statement_start_offset/2) + 1)	ELSE 0			END,
						CASE WHEN br.statement_end_offset	> 0 THEN ((br.statement_end_offset/2))			ELSE 2147483647 END) AS blocking_sqltext
			--, blocking_sqltext.text AS blocking_sqltext
			, s.program_name
			, s.host_name
			, s.client_interface_name
			--, *
		FROM sys.dm_exec_requests r
			INNER JOIN sys.dm_exec_sessions as s
				ON s.session_id = r.session_id
			OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS sqltext 	
			LEFT JOIN sys.dm_exec_requests br
				ON br.session_id = r.blocking_session_id
			OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) AS blocking_sqltext 
		WHERE s.is_user_process = 'true'
			AND s.session_id <> @@SPID
			AND (@sspid IS NULL
				OR s.session_id = @sspid 
				OR ( @sspid < 0 AND s.session_id <> ABS(@sspid) ))
		OPTION (OPTIMIZE FOR (@n=1))
END



GO
