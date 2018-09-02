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
-- Create date: 10/06/2016
-- Description:	Process the server status information collected in [dbo].[ServerStatus_Loading]
--
-- Log:
--				10/06/2016	RAG	Created
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessServerStatus] 
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @tableHTML		NVARCHAR(MAX) ;
	DECLARE @emailSubject	NVARCHAR(128) = 'SQL Server Services Changes'


	IF OBJECT_ID('tempdb..#h') IS NOT NULL DROP TABLE #h

	IF NOT EXISTS (SELECT * FROM dbo.ServerStatus_Loading) BEGIN
		RAISERROR ('The table [dbo].[ServerStatus_Loading] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	
	BEGIN TRY

		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT [server_name],[DisplayName],[Name],[State],[Status],[StartMode],[StartName],[DateCollectionTime],[RowCheckSum]
			INTO #h
			FROM dbo.ServerStatus
			WHERE 1=0
		
		INSERT INTO #h
		SELECT [server_name],[DisplayName],[Name],[State],[Status],[StartMode],[StartName],[DateCollectionTime],[RowCheckSum]
			FROM (
			MERGE INTO dbo.ServerStatus t
				USING dbo.ServerStatus_Loading AS s
					ON s.server_name = t.server_name
						AND s.Name = t.Name
				WHEN NOT MATCHED THEN 
					INSERT ([server_name],[DisplayName],[Name],[State],[Status],[StartMode],[StartName],[DateCollectionTime],[RowCheckSum])
					VALUES ([server_name],[DisplayName],[Name],[State],[Status],[StartMode],[StartName],[DateCollectionTime],[RowCheckSum])
			
				WHEN MATCHED THEN 
					UPDATE
						SET 
							t.[server_name]				= s.[server_name]
							, t.[DisplayName]			= s.[DisplayName]
							, t.[Name]					= s.[Name]
							, t.[State]					= s.[State]
							, t.[Status]				= s.[Status]
							, t.[StartMode]				= s.[StartMode]
							, t.[StartName]				= s.[StartName]
							, t.[DateCollectionTime]	= s.[DateCollectionTime]
							, t.[RowCheckSum]			= s.[RowCheckSum]
			OUTPUT $action AS [Action], deleted.*) AS History 
		WHERE [Action] IN ('UPDATE', 'DELETE');


			SET @tableHTML =
				N'<html><head><style type="text/css">.ac {text-align:center}.diff {color:red} th{background-color:#5B9BD5;color:white;font-weight:bold}</style></head><body>' +
				N'<table border="1">' +
				N'<tr class="ac"><th>server_name</th>' + 
				N'<th>DisplayName</th>' +
				N'<th>Name</th>' +
				N'<th>old_State</th>' +
				N'<th>new_State</th>' +
				N'<th>old_Status</th>' +
				N'<th>new_Status</th>' +
				N'<th>old_StartMode</th>' +
				N'<th>new_StartMode</th>' +
				N'<th>old_StartName</th>' +
				N'<th>new_StartName</th>' +

				N'<th>DateCollectionTime</th></tr>'


			;WITH cte AS (

				SELECT	old.server_name, 
						'<td>' + old.[server_name]			+ '</td>' +
						'<td>' + old.[DisplayName]			+ '</td>' +
						'<td>' + old.[Name]					+ '</td>' +
						'<td' + CASE WHEN old.[State]		<> new.[State]		THEN ' class="diff"' ELSE '' END + '>' + old.[State]		+ '</td>' +
						'<td' + CASE WHEN old.[State]		<> new.[State]		THEN ' class="diff"' ELSE '' END + '>' + new.[State]		+ '</td>' +
						'<td' + CASE WHEN old.[Status]		<> new.[Status]		THEN ' class="diff"' ELSE '' END + '>' + old.[Status]		+ '</td>' +
						'<td' + CASE WHEN old.[Status]		<> new.[Status]		THEN ' class="diff"' ELSE '' END + '>' + new.[Status]		+ '</td>' +
						'<td' + CASE WHEN old.[StartMode]	<> new.[StartMode]	THEN ' class="diff"' ELSE '' END + '>' + old.[StartMode]	+ '</td>' +
						'<td' + CASE WHEN old.[StartMode]	<> new.[StartMode]	THEN ' class="diff"' ELSE '' END + '>' + new.[StartMode]	+ '</td>' +
						'<td' + CASE WHEN old.[StartName]	<> new.[StartName]	THEN ' class="diff"' ELSE '' END + '>' + old.[StartName]	+ '</td>' +
						'<td' + CASE WHEN old.[StartName]	<> new.[StartName]	THEN ' class="diff"' ELSE '' END + '>' + new.[StartName]	+ '</td>' +
						'<td>' + CONVERT(NVARCHAR, new.[DateCollectionTime], 103) + ' ' + CONVERT(NVARCHAR, new.[DateCollectionTime], 108)	+ '</td>' AS HTMLRow
				FROM #h AS old
					INNER JOIN dbo.ServerStatus AS new
						ON new.server_name = old.server_name
							AND new.Name = old.Name
							AND new.RowCheckSum <> old.RowCheckSum
			)
			SELECT @tableHTML += ( SELECT '<tr>' + HTMLRow + '</tr>'
									FROM cte						
									ORDER BY cte.server_name 
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

		TRUNCATE TABLE dbo.ServerStatus_Loading

	END TRY
	BEGIN CATCH
		SELECT ERROR_MESSAGE();
	END CATCH
END
GO
