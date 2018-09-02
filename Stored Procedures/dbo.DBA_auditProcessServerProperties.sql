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
-- Create date: 21/05/2013
-- Description:	Process the Instance information collected in [dbo].[ServerProperties_Loading]
--
-- Log:
--				12/03/2018	RAG	- Added email alert when something has changed
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessServerProperties] 
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @SQLtableHTML	NVARCHAR(MAX);
	DECLARE @tableHTML		NVARCHAR(MAX) = '';
	DECLARE @HTML			NVARCHAR(MAX);
	DECLARE @emailSubject	NVARCHAR(128) = 'Server Properties Change';

	IF NOT EXISTS (SELECT * FROM dbo.ServerProperties_Loading) BEGIN
		RAISERROR ('The table [dbo].[ServerProperties_Loading] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	BEGIN TRY
		BEGIN TRAN

		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT [Action],[server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
				,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
				,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
				,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
				,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime],[RowCheckSum]
			INTO #h
			FROM dbo.ServerProperties_History
			WHERE 1=0
		
		INSERT INTO #h ([Action],[server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
						,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
						,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
						,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
						,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime],[RowCheckSum])
		SELECT [Action],[server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
				,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
				,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
				,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
				,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime],[RowCheckSum]
			FROM (

			-- Get current information into the table
			MERGE INTO dbo.ServerProperties AS t
				USING dbo.ServerProperties_Loading AS s
					ON t.server_name = s.server_name

				WHEN NOT MATCHED BY TARGET THEN 
					INSERT ([server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
							,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
							,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
							,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
							,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime])
					VALUES ([server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
							,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
							,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
							,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
							,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime])

				WHEN MATCHED THEN UPDATE
					SET t.[BackupDirectory]					= s.[BackupDirectory]
						, t.[BuildClrVersion]				= s.[BuildClrVersion]
						, t.[Collation]						= s.[Collation]
						, t.[CollationID]					= s.[CollationID]
						, t.[ComparisonStyle]				= s.[ComparisonStyle]
						, t.[ComputerNamePhysicalNetBIOS]	= s.[ComputerNamePhysicalNetBIOS]
						, t.[Edition]						= s.[Edition]
						, t.[EditionID]						= s.[EditionID]
						, t.[EngineEdition]					= s.[EngineEdition]
						, t.[FilestreamConfiguredLevel]		= s.[FilestreamConfiguredLevel]
						, t.[FilestreamEffectiveLevel]		= s.[FilestreamEffectiveLevel]
						, t.[FilestreamShareName]			= s.[FilestreamShareName]
						, t.[HadrManagerStatus]				= s.[HadrManagerStatus]
						, t.[InstanceDefaultDataPath]		= s.[InstanceDefaultDataPath]
						, t.[InstanceDefaultLogPath]		= s.[InstanceDefaultLogPath]
						, t.[InstanceName]					= s.[InstanceName]
						, t.[IsClustered]					= s.[IsClustered]
						, t.[IsFullTextInstalled]			= s.[IsFullTextInstalled]
						, t.[IsHadrEnabled]					= s.[IsHadrEnabled]
						, t.[IsIntegratedSecurityOnly]		= s.[IsIntegratedSecurityOnly]
						, t.[IsLocalDB]						= s.[IsLocalDB]
						, t.[IsSingleUser]					= s.[IsSingleUser]
						, t.[IsXTPSupported]				= s.[IsXTPSupported]
						, t.[LCID]							= s.[LCID]
						, t.[LicenseType]					= s.[LicenseType]
						, t.[MachineName]					= s.[MachineName]
						, t.[NumLicenses]					= s.[NumLicenses]
						, t.[ProcessID]						= s.[ProcessID]
						, t.[ProductLevel]					= s.[ProductLevel]
						, t.[ProductVersion]				= s.[ProductVersion]
						, t.[ResourceLastUpdateDateTime]	= s.[ResourceLastUpdateDateTime]
						, t.[ResourceVersion]				= s.[ResourceVersion]
						, t.[ServerName]					= s.[ServerName]
						, t.[SqlCharSet]					= s.[SqlCharSet]
						, t.[SqlCharSetName]				= s.[SqlCharSetName]
						, t.[SqlSortOrder]					= s.[SqlSortOrder]
						, t.[SqlSortOrderName]				= s.[SqlSortOrderName]
						, t.[DataCollectionTime]			= s.[DataCollectionTime]
						
				WHEN NOT MATCHED BY SOURCE AND t.server_name NOT IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor]) THEN 
					DELETE
			OUTPUT $action AS [Action], deleted.*) AS History 
		WHERE [Action] IN ('UPDATE', 'DELETE');
			
		
		MERGE dbo.ServerProperties_History AS t
			USING #h AS s
				ON s.server_name = t.server_name
					AND s.[RowCheckSum] = t.[RowCheckSum]
			WHEN NOT MATCHED THEN 
					INSERT ([Action],[server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
						,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
						,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
						,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
						,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime],[RowCheckSum])
					VALUES ([Action],[server_name],[BackupDirectory],[BuildClrVersion],[Collation],[CollationID],[ComparisonStyle],[ComputerNamePhysicalNetBIOS],[Edition],[EditionID]
						,[EngineEdition],[FilestreamConfiguredLevel],[FilestreamEffectiveLevel],[FilestreamShareName],[HadrManagerStatus],[InstanceDefaultDataPath],[InstanceDefaultLogPath]
						,[InstanceName],[IsClustered],[IsFullTextInstalled],[IsHadrEnabled],[IsIntegratedSecurityOnly],[IsLocalDB],[IsSingleUser],[IsXTPSupported],[LCID],[LicenseType]
						,[MachineName],[NumLicenses],[ProcessID],[ProductLevel],[ProductVersion],[ResourceLastUpdateDateTime],[ResourceVersion],[ServerName],[SqlCharSet]
						,[SqlCharSetName],[SqlSortOrder],[SqlSortOrderName],[DataCollectionTime],[RowCheckSum]);
					
		TRUNCATE TABLE dbo.ServerProperties_Loading

		COMMIT;

		-- This query will return the differences between the new and old records.
		SET @SQLtableHTML = 'SET @tableHTML = (SELECT CONVERT(VARCHAR(MAX), ''<tr><td class="h">[server_name]</td><td class="h" colspan="2">'' + ISNULL(CONVERT(VARCHAR(256), del.server_name), '''') + ''</td>''';

		SET @SQLtableHTML += ( SELECT ' + CASE WHEN ISNULL(CONVERT(VARCHAR(256),ins.'+ QUOTENAME(name) +'),'''') <> ISNULL(CONVERT(VARCHAR(256),del.'+ QUOTENAME(name) +'),'''') THEN ''<tr><td>' 
										+  name 
										+ '</td><td class="d">'' + ISNULL(CONVERT(VARCHAR(256), del.' 
										+ QUOTENAME(name) + '), '''') + ''</td><td class="i">'' + ISNULL(CONVERT(VARCHAR(256), ins.'
										+ QUOTENAME(name) + '), '''') + ''</td></tr>'' ELSE '''' END' + CHAR(10)
									FROM sys.columns
									WHERE object_id = OBJECT_ID('dbo.ServerProperties')
										AND name NOT IN ('ID', 'server_name', 'RowCheckSum')
									ORDER BY column_id 
									FOR XML PATH(''))
						
		SET @SQLtableHTML += ')
					FROM #h	AS del	
						INNER JOIN dbo.ServerProperties AS ins
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
						INNER JOIN dbo.ServerProperties AS ins
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
