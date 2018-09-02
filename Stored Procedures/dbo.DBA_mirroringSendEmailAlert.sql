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
-- Create date: 24/10/2013
-- Description:	Sends en email with the current status of the mirroring sessions
-- 
-- Usage:
--				To be called in a job in response a mirroring event alert
--
-- Change Log:	22/11/2013	RAG	Added funtionality to avoid multiple repetitive emails, this usually happens because alerts are triggered faster
--									than emails are sent.
--				11/12/2013	RAG	Added column mirroring_change_date
--				01/08/2015	RAG	Added column mirroring_safety_level to the comparison to see if something has changed
-- =============================================
CREATE PROCEDURE [dbo].[DBA_mirroringSendEmailAlert]	
AS 
BEGIN
	
	SET NOCOUNT ON
	SET QUOTED_IDENTIFIER ON -- Keep it!

	DECLARE @emailSubject NVARCHAR(128) = 'Mirroring Status has changed for a database in ' + QUOTENAME(@@SERVERNAME)

	DECLARE @tableHTML  NVARCHAR(MAX) ;

	SET @tableHTML =
		N'<html><head><style type="text/css">.ac {text-align:center}</style></head><boby>' +
		N'<table border="1">' +
		N'<tr class="ac"><th>DatabaseName</th>' + 
		N'<th>mirroring_role</th>' +
		N'<th>mirroring_state</th>' +
		N'<th>witness_state</th>' +
		N'<th>safety_level</th>' +
		N'<th>mirroring_change_date</th></tr>'

	-- Update the values for the last mirroring status
	MERGE dbo.LastMirroringStatus AS t
		USING (SELECT @@SERVERNAME AS server_name
						, DB_NAME(database_id) AS DatabaseName
						, mirroring_role
						, mirroring_role_desc
						, mirroring_state
						, mirroring_state_desc
						, mirroring_witness_state
						, mirroring_witness_state_desc
						, mirroring_safety_level
						, mirroring_safety_level_desc
					FROM sys.database_mirroring 
					WHERE mirroring_state IS NOT NULL) AS s
		ON t.DatabaseName = s.DatabaseName 
			AND t.server_name = s.server_name
		WHEN MATCHED 
			AND (	t.mirroring_role			<> s.mirroring_role
				OR t.mirroring_state			<> s.mirroring_state
				OR t.mirroring_safety_level		<> s.mirroring_safety_level
				OR t.mirroring_witness_state	<> s.mirroring_witness_state) 
			THEN UPDATE 
				SET t.mirroring_role				= s.mirroring_role
					, t.mirroring_role_desc			= s.mirroring_role_desc
					, t.mirroring_state				= s.mirroring_state
					, t.mirroring_state_desc		= s.mirroring_state_desc
					, t.mirroring_witness_state		= s.mirroring_witness_state
					, t.mirroring_witness_state_desc= s.mirroring_witness_state_desc
					, t.mirroring_safety_level		= s.mirroring_safety_level
					, t.mirroring_safety_level_desc	= s.mirroring_safety_level_desc
					, t.mirroring_change_date		= GETDATE()
		WHEN NOT MATCHED BY TARGET
			THEN INSERT ( server_name, DatabaseName, mirroring_role, mirroring_role_desc, mirroring_state, mirroring_state_desc, mirroring_witness_state
						, mirroring_witness_state_desc, mirroring_safety_level, mirroring_safety_level_desc, mirroring_change_date )
				VALUES  ( s.server_name, s.DatabaseName, s.mirroring_role, s.mirroring_role_desc, s.mirroring_state, s.mirroring_state_desc, s.mirroring_witness_state
						, s.mirroring_witness_state_desc, s.mirroring_safety_level, s.mirroring_safety_level_desc, GETDATE() );
	
	-- IF something has really changed, lets send the email
	IF @@ROWCOUNT > 0 BEGIN
		;WITH cte AS (
		SELECT TOP 100 PERCENT
					 '<td>' + DatabaseName + '</td>'  
							+ '<td class="ac">' + mirroring_role_desc + '</td>'  
							+ '<td class="ac">' + CASE 
										WHEN mirroring_state = 0 THEN '<span style="color:magenta">'
										WHEN mirroring_state = 1 THEN '<span style="color:red">'
										WHEN mirroring_state = 2 THEN '<span style="color:orange">'
										WHEN mirroring_state = 3 THEN '<span style="color:orange">'
										WHEN mirroring_state = 4 THEN '<span style="color:green">'
										WHEN mirroring_state = 5 THEN '<span style="color:brown">'
										WHEN mirroring_state = 6 THEN '<span style="color:blue">'
										ELSE '<span style="color:red">'
									END + 			
							mirroring_state_desc 
							+ '</span></td>'
							+ '<td class="ac">' + CASE 
										WHEN mirroring_witness_state = 0 THEN '<span style="color:orange">'
										WHEN mirroring_witness_state = 1 THEN '<span style="color:green">'
										WHEN mirroring_witness_state = 2 THEN '<span style="color:red">'
										ELSE '<span style="color:red">'
									END + 			
							mirroring_witness_state_desc 
							+ '</span></td>'
							+ '<td class="ac">' + CASE 
										WHEN mirroring_safety_level = 0 THEN '<span style="color:red">'
										WHEN mirroring_safety_level = 1 THEN '<span style="color:orange">'
										WHEN mirroring_safety_level = 2 THEN '<span style="color:green">'
										ELSE '<span style="color:red">'
									END + 			
							mirroring_safety_level_desc 
							+ '</span></td>'
							+ '<td class="ac">' + CONVERT(VARCHAR, mirroring_change_date, 103) + ' ' +  CONVERT(VARCHAR, mirroring_change_date, 108) + '</td>'
							  AS HTMLRow
					, DatabaseName
				FROM DBA.dbo.LastMirroringStatus 
				WHERE mirroring_state IS NOT NULL 
					AND server_name = @@SERVERNAME
		)
		SELECT @tableHTML += ( SELECT '<tr>' + HTMLRow + '</tr>'
								FROM cte						
								ORDER BY DatabaseName 
								FOR XML PATH(''), TYPE ).value('/', 'NVARCHAR(MAX)') + '</table></body></html>'

		EXEC msdb.dbo.sp_send_dbmail 
			@profile_name = 'Admin Profile', 
			@recipients = 'DatabaseAdministrators@rws.com', 
			@subject = @emailSubject,
			@body = @tableHTML,  
			@body_format = 'HTML'
	END
END




GO
