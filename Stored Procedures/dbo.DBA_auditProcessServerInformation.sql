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
-- Create date: 11/02/2015
-- Description:	Process the server information collected in [dbo].[ServerInformation_Loading] 
-- Log:
--				21/05/2013	RAG - Created as Stored Procedure
--				21/05/2013	RAG - Created flag isAcessible for ServerInformation table
--				21/05/2013	RAG - Added case WHEN NOT MATCHED BY SOURCE to flag not accesible servers with isAcessible = 0
--				08/01/2014	RAG - Added Column IP Address
--				08/01/2014	RAG - When CSDVersion is null then RTM
--				13/11/2014	RAG - Included INSERT into _history tables
--				08/04/2015	RAG - changed some columns to match the new table's structure 
--				06/04/2016	SZO - Added column for [power_plan]
--				30/01/2018	SZO - Added emailing when [power_plan] is changed
--				07/03/2018	RAG - Added email alert for any change in the configuration
--				07/03/2018	RAG - Changed the format of the table to display as a list and only the values that have changed
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessServerInformation] 
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @SQLtableHTML	NVARCHAR(MAX);
	DECLARE @tableHTML		NVARCHAR(MAX) = '';
	DECLARE @HTML			NVARCHAR(MAX);
	DECLARE @emailSubject	NVARCHAR(128) = 'Server Information Change';

	IF NOT EXISTS (SELECT * FROM dbo.ServerInformation_Loading) BEGIN
		RAISERROR ('The table [dbo].[ServerInformation_Loading] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	BEGIN TRY

		BEGIN TRAN 		
		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT [Action], server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
					, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan, RowCheckSum
			INTO #h
			FROM dbo.ServerInformation_History
			WHERE 1=0
		
		-- server information
		INSERT #h ([Action], server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
					, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan, RowCheckSum)
			SELECT [Action], server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
					, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan, RowCheckSum
				FROM (
					MERGE INTO dbo.ServerInformation t 
						USING dbo.ServerInformation_Loading AS s
							ON t.server_name = s.server_name	
						WHEN MATCHED 
							THEN UPDATE
								SET t.OS						= s.OS
									, t.OSArchitecture			= s.OSArchitecture
									, t.OSPatchLevel			= s.OSPatchLevel
									, t.OSVersion				= s.OSVersion
									, t.LastBootUpTime			= s.LastBootUpTime
									, t.TotalVisibleMemorySize	= s.TotalVisibleMemorySize
									, t.TotalPhysicalMemorySize = s.TotalPhysicalMemorySize
									, t.TotalMemoryModules		= s.TotalMemoryModules
									, t.IPAddress				= s.IPAddress
									, t.physical_cpu_count		= s.physical_cpu_count
									, t.cores_per_cpu			= s.cores_per_cpu
									, t.logical_cpu_count		= s.logical_cpu_count
									, t.manufacturer			= s.manufacturer
									, t.server_model			= s.server_model
									, t.processor_name			= s.processor_name
									, t.DataCollectionTime		= s.DataCollectionTime
									, t.isAccessible			= 1
									, t.power_plan				= s.power_plan
			
						WHEN NOT MATCHED BY TARGET
							THEN INSERT (server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
											, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan)
								VALUES (s.server_name, s.OS, s.OSArchitecture, s.OSPatchLevel, s.OSVersion, s.LastBootUpTime, s.TotalVisibleMemorySize, s.TotalPhysicalMemorySize, s.TotalMemoryModules
											, s.IPAddress, s.physical_cpu_count, s.cores_per_cpu, s.logical_cpu_count, s.manufacturer, s.server_model, s.processor_name, s.DataCollectionTime, 1, power_plan)
		
						-- If we're not monitoring the server anymore, just delete, history would be always available 
						WHEN NOT MATCHED BY SOURCE AND t.server_name NOT IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor]) THEN 
							DELETE
						-- If we're monitoring the server, flaggit as not accessible to further investigate 
						WHEN NOT MATCHED BY SOURCE AND t.server_name IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor]) THEN 
							UPDATE 
								SET t.isAccessible			= 0
					OUTPUT $action AS [Action], deleted.*
				) AS History WHERE [Action] IN ('UPDATE', 'DELETE');
			
		MERGE INTO dbo.ServerInformation_History AS t
			USING #h AS s
				ON s.server_name = t.server_name
					AND s.RowCheckSum = t.RowCheckSum
			WHEN NOT MATCHED THEN 
				INSERT ([Action], server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
							, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan, RowCheckSum)
				VALUES ([Action], server_name, OS, OSArchitecture, OSPatchLevel, OSVersion, LastBootUpTime, TotalVisibleMemorySize, TotalPhysicalMemorySize, TotalMemoryModules
							, IPAddress, physical_cpu_count, cores_per_cpu, logical_cpu_count, manufacturer, server_model, processor_name, DataCollectionTime, isAccessible, power_plan, RowCheckSum);
		
		
		TRUNCATE TABLE dbo.ServerInformation_Loading;
	
		COMMIT 


		-- This query will return the differences between the new and old records.
		SET @SQLtableHTML = 'SET @tableHTML = (SELECT CONVERT(VARCHAR(MAX), ''<tr><td class="h">[server_name]</td><td class="h" colspan="2">'' + ISNULL(CONVERT(VARCHAR(256), del.server_name), '''') + ''</td>''';

		SET @SQLtableHTML += ( SELECT ' + CASE WHEN ISNULL(CONVERT(VARCHAR(256),ins.'+ QUOTENAME(name) +'),'''') <> ISNULL(CONVERT(VARCHAR(256),del.'+ QUOTENAME(name) +'),'''') THEN ''<tr><td>' 
										+  name 
										+ '</td><td class="d">'' + ISNULL(CONVERT(VARCHAR(256), del.' 
										+ QUOTENAME(name) + '), '''') + ''</td><td class="i">'' + ISNULL(CONVERT(VARCHAR(256), ins.'
										+ QUOTENAME(name) + '), '''') + ''</td></tr>'' ELSE '''' END' 

									FROM sys.columns
									WHERE object_id = OBJECT_ID('dbo.ServerInformation')
										AND name NOT IN ('ID', 'server_name', 'RowCheckSum')
									ORDER BY column_id 
									FOR XML PATH(''))

		SET @SQLtableHTML += ')
					FROM #h	AS del	
						INNER JOIN dbo.ServerInformation AS ins
							ON ins.server_name = del.server_name
					WHERE del.RowCheckSum <> ins.RowCheckSum
					ORDER BY ins.server_name
					FOR XML PATH(''''));
					';

		-- After generating the string using FOR XML, these simbols get replaced by their HTML entities, so we need them back
		SET @SQLtableHTML = REPLACE(REPLACE(@SQLtableHTML, '&lt;', '<'), '&gt;', '>');

		EXECUTE sp_executesql @stmt = @SQLtableHTML, @params = N'@tableHTML NVARCHAR(MAX) OUTPUT', @tableHTML = @tableHTML OUTPUT

		-- The query above also generates symbols that were replaced by their HTML entities, so we need them back
		SET @tableHTML = REPLACE(REPLACE(@tableHTML, '&lt;', '<'), '&gt;', '>');

		SET @HTML = N'<html><head><style type="text/css">.ac{text-align:center}.diff {color:red} th{background-color:#5B9BD5;color:white;font-weight:bold;width:250px} td {white-space:nowrap;} .i{color:green;} .d{color:red;} .h{background-color:lightblue;font-weight:bold;}</style></head><body>'
						+ N'<table border="1">'
						+ N'<tr class="ac">'
						+ N'<th>Configuration Name</th>' 						
						+ N'<th>Previous Value</th>'
						+ N'<th>Current Value</th></tr>'
						+ @tableHTML
						+ '</table>'
						+ '</body></html>';

		SELECT @HTML

		IF EXISTS (SELECT 1 
						FROM #h	AS del	
							INNER JOIN dbo.ServerInformation AS ins
								ON ins.server_name = del.server_name
						WHERE del.RowCheckSum <> ins.RowCheckSum) BEGIN
			EXEC msdb.dbo.sp_send_dbmail @profile_name = 'Admin Profile'
			  , @recipients = 'DatabaseAdministrators@rws.com'
			  , @subject = @emailSubject
			  , @body = @HTML
			  , @body_format = 'HTML';
		END;

	END TRY
	BEGIN CATCH
		SELECT ERROR_MESSAGE();
		ROLLBACK
	END CATCH;

END
GO
