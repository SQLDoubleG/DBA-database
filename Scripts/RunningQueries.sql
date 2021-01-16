SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON
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
--				22/11/2018 RAG	- sspid will look for blocking_session_id
--								- Added parameter @loginName
--				02/07/2019 RAG	- Added XML conversion to sqltext (borrowed from sp_WhoIsActive)
--				09/12/2019 RAG	- Added [outer_sqltext] and [reads] columns
--				16/01/2021 RAG	- Removed dependencies to allow run it in Azure SQL DB
--
-- =============================================

DECLARE @sspid	int 
DECLARE @loginName SYSNAME  --= 'domain\user'
DECLARE @n INT = 2147483647

SELECT TOP (@n)
		ISNULL(NULLIF( CONVERT(VARCHAR(24), (DATEDIFF(SECOND, r.start_time, GETDATE())) / 3600 / 24 ),'0') + '.', '') + 
			RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, r.start_time, GETDATE())) / 3600 % 24 ), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, r.start_time, GETDATE())) / 60 % 60), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, r.start_time, GETDATE())) % 60), 2) AS execution_time


		, r.session_id
		, r.blocking_session_id
		, r.percent_complete
		, (SELECT
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
					N'--' + NCHAR(13) + NCHAR(10) +
					
					 (SELECT SUBSTRING(sqltext.text,
					CASE WHEN r.statement_start_offset	> 0 THEN ((r.statement_start_offset/2) + 1)	ELSE 0			END,
					CASE WHEN r.statement_end_offset	> 0 THEN ((r.statement_end_offset/2))		ELSE 2147483647 END)
						)

					 +
			NCHAR(13) + NCHAR(10) + N'--' COLLATE Latin1_General_Bin2,
			NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
			NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
			NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
			NCHAR(0),N'') AS [processing-instruction(query)]
		FOR XML
			PATH(''),
			TYPE
		) as [sqltext]
		/*
		, (SELECT
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
					N'--' + NCHAR(13) + NCHAR(10) +
					
					 (sqltext.text)

					 +
			NCHAR(13) + NCHAR(10) + N'--' COLLATE Latin1_General_Bin2,
			NCHAR(31),N'?'),NCHAR(30),N'?'),NCHAR(29),N'?'),NCHAR(28),N'?'),NCHAR(27),N'?'),NCHAR(26),N'?'),NCHAR(25),N'?'),NCHAR(24),N'?'),NCHAR(23),N'?'),NCHAR(22),N'?'),
			NCHAR(21),N'?'),NCHAR(20),N'?'),NCHAR(19),N'?'),NCHAR(18),N'?'),NCHAR(17),N'?'),NCHAR(16),N'?'),NCHAR(15),N'?'),NCHAR(14),N'?'),NCHAR(12),N'?'),
			NCHAR(11),N'?'),NCHAR(8),N'?'),NCHAR(7),N'?'),NCHAR(6),N'?'),NCHAR(5),N'?'),NCHAR(4),N'?'),NCHAR(3),N'?'),NCHAR(2),N'?'),NCHAR(1),N'?'),
			NCHAR(0),N'') AS [processing-instruction(query)]
		FOR XML
			PATH(''),
			TYPE
		) as [outer_sqltext]
		--*/
		, DB_NAME(r.database_id) as database_Name
		, s.login_name
		, r.status
		, r.command
		, r.wait_type + CASE WHEN ISNULL(r.wait_resource, '') <> '' THEN ' (' + r.wait_resource + ')' ELSE '' END AS wait_type
		, case	when r.percent_complete = 0 THEN NULL
				else DATEADD (ss,DATEDIFF (ss,r.start_time,getdate()) / r.percent_complete * 100, r.start_time) 
			end AS Expected_end_time 
		, r.cpu_time
		, r.reads
		, r.total_elapsed_time
		, r.granted_query_memory
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
		AND s.login_name = ISNULL(@loginName, s.login_name)
		AND (@sspid IS NULL
			OR s.session_id = @sspid 
			OR r.blocking_session_id = @sspid 
			OR ( @sspid < 0 AND s.session_id <> ABS(@sspid)))

		/* All sessions that participate in blocking
		AND (r.blocking_session_id <> 0 
			OR r.session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests))			
		--*/

	ORDER BY r.start_time ASC
	OPTION (OPTIMIZE FOR (@n=1))

GO
