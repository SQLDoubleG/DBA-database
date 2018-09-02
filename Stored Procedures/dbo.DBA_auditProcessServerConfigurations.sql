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
-- Create date: 11/02/2015
-- Description:	Process the server configurations collected by [dbo].[ServerConfigurations_Loading]
--				
-- Log:
--				12/03/2018	RAG	- Added email alert when something has changed
-- 
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessServerConfigurations] 
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @SQLtableHTML	NVARCHAR(MAX);
	DECLARE @tableHTML		NVARCHAR(MAX) = '';
	DECLARE @HTML			NVARCHAR(MAX);
	DECLARE @emailSubject	NVARCHAR(128) = 'Server Configuration Change';

	IF NOT EXISTS (SELECT * FROM dbo.ServerConfigurations_Loading) BEGIN
		RAISERROR ('The table [dbo].[ServerConfigurations_Loading] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	BEGIN TRY
		BEGIN TRAN

		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT * 
			INTO #h
			FROM dbo.ServerConfigurations_History
			WHERE 1=0
		
		INSERT INTO #h ([Action],[server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
						,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
						,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
						,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
						,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)],[ft crawl bandwidth (max)]
						,[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)],[in-doubt xact resolution]
						,[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)],[max text repl size (B)]
						,[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers],[network packet size (B)]
						,[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank],[priority boost]
						,[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections],[remote login timeout (s)]
						,[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion],[set working set size]
						,[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections],[user options]
						,[xp_cmdshell],[trace_flags_enabled],[BackupRootPath],[LogFilesRootPath],[KeepNBackups],[DataCollectionTime],[RowCheckSum])
		
		SELECT [Action],[server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
				,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
				,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
				,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
				,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)],[ft crawl bandwidth (max)]
				,[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)],[in-doubt xact resolution]
				,[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)],[max text repl size (B)]
				,[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers],[network packet size (B)]
				,[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank],[priority boost]
				,[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections],[remote login timeout (s)]
				,[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion],[set working set size]
				,[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections],[user options]
				,[xp_cmdshell],[trace_flags_enabled],[BackupRootPath],[LogFilesRootPath],[KeepNBackups],[DataCollectionTime],[RowCheckSum]
			FROM (
				MERGE dbo.ServerConfigurations AS t
							USING dbo.ServerConfigurations_Loading AS s
								ON s.server_name = t.server_name
					WHEN NOT MATCHED THEN 
						INSERT ([server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
							,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
							,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
							,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
							,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)]
							,[ft crawl bandwidth (max)],[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)]
							,[in-doubt xact resolution],[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)]
							,[max text repl size (B)],[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers]
							,[network packet size (B)],[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank]
							,[priority boost],[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections]
							,[remote login timeout (s)],[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion]
							,[set working set size],[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections]
							,[user options],[xp_cmdshell],[trace_flags_enabled],[DataCollectionTime])
					VALUES ([server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
							,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
							,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
							,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
							,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)]
							,[ft crawl bandwidth (max)],[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)]
							,[in-doubt xact resolution],[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)]
							,[max text repl size (B)],[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers]
							,[network packet size (B)],[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank]
							,[priority boost],[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections]
							,[remote login timeout (s)],[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion]
							,[set working set size],[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections]
							,[user options],[xp_cmdshell],[trace_flags_enabled],[DataCollectionTime])
					WHEN MATCHED THEN
						UPDATE SET
							  t.[access check cache bucket count]	= s.[access check cache bucket count]
							, t.[access check cache quota]		   	= s.[access check cache quota]
							, t.[Ad Hoc Distributed Queries]		= s.[Ad Hoc Distributed Queries]
							, t.[affinity I/O mask]				   	= s.[affinity I/O mask]
							, t.[affinity mask]					   	= s.[affinity mask]
							, t.[affinity64 I/O mask]				= s.[affinity64 I/O mask]
							, t.[affinity64 mask]					= s.[affinity64 mask]
							, t.[Agent XPs]						   	= s.[Agent XPs]
							, t.[allow updates]					   	= s.[allow updates]
							, t.[awe enabled]						= s.[awe enabled]
							, t.[backup checksum default]			= s.[backup checksum default]
							, t.[backup compression default]		= s.[backup compression default]
							, t.[blocked process threshold (s)]	   	= s.[blocked process threshold (s)]
							, t.[c2 audit mode]					   	= s.[c2 audit mode]
							, t.[clr enabled]						= s.[clr enabled]
							, t.[common criteria compliance enabled]= s.[common criteria compliance enabled]
							, t.[contained database authentication] = s.[contained database authentication]
							, t.[cost threshold for parallelism]	= s.[cost threshold for parallelism]
							, t.[cross db ownership chaining]		= s.[cross db ownership chaining]
							, t.[cursor threshold]				   	= s.[cursor threshold]
							, t.[Database Mail XPs]				   	= s.[Database Mail XPs]
							, t.[default full-text language]		= s.[default full-text language]
							, t.[default language]				   	= s.[default language]
							, t.[default trace enabled]			   	= s.[default trace enabled]
							, t.[disallow results from triggers]	= s.[disallow results from triggers]
							, t.[EKM provider enabled]			   	= s.[EKM provider enabled]
							, t.[filestream access level]			= s.[filestream access level]
							, t.[fill factor (%)]					= s.[fill factor (%)]
							, t.[ft crawl bandwidth (max)]		   	= s.[ft crawl bandwidth (max)]
							, t.[ft crawl bandwidth (min)]		   	= s.[ft crawl bandwidth (min)]
							, t.[ft notify bandwidth (max)]		   	= s.[ft notify bandwidth (max)]
							, t.[ft notify bandwidth (min)]		   	= s.[ft notify bandwidth (min)]
							, t.[index create memory (KB)]		   	= s.[index create memory (KB)]
							, t.[in-doubt xact resolution]		   	= s.[in-doubt xact resolution]
							, t.[lightweight pooling]				= s.[lightweight pooling]
							, t.[locks]							   	= s.[locks]
							, t.[max degree of parallelism]		   	= s.[max degree of parallelism]
							, t.[max full-text crawl range]		   	= s.[max full-text crawl range]
							, t.[max server memory (MB)]			= s.[max server memory (MB)]
							, t.[max text repl size (B)]			= s.[max text repl size (B)]
							, t.[max worker threads]				= s.[max worker threads]
							, t.[media retention]					= s.[media retention]
							, t.[min memory per query (KB)]		   	= s.[min memory per query (KB)]
							, t.[min server memory (MB)]			= s.[min server memory (MB)]
							, t.[nested triggers]					= s.[nested triggers]
							, t.[network packet size (B)]			= s.[network packet size (B)]
							, t.[Ole Automation Procedures]		   	= s.[Ole Automation Procedures]
							, t.[open objects]					   	= s.[open objects]
							, t.[optimize for ad hoc workloads]	   	= s.[optimize for ad hoc workloads]
							, t.[PH timeout (s)]					= s.[PH timeout (s)]
							, t.[precompute rank]					= s.[precompute rank]
							, t.[priority boost]					= s.[priority boost]
							, t.[query governor cost limit]		   	= s.[query governor cost limit]
							, t.[query wait (s)]					= s.[query wait (s)]
							, t.[recovery interval (min)]			= s.[recovery interval (min)]
							, t.[remote access]					   	= s.[remote access]
							, t.[remote admin connections]		   	= s.[remote admin connections]
							, t.[remote login timeout (s)]		   	= s.[remote login timeout (s)]
							, t.[remote proc trans]				   	= s.[remote proc trans]
							, t.[remote query timeout (s)]		   	= s.[remote query timeout (s)]
							, t.[Replication XPs]					= s.[Replication XPs]
							, t.[scan for startup procs]			= s.[scan for startup procs]
							, t.[server trigger recursion]		   	= s.[server trigger recursion]
							, t.[set working set size]			   	= s.[set working set size]
							, t.[show advanced options]			   	= s.[show advanced options]
							, t.[SMO and DMO XPs]					= s.[SMO and DMO XPs]
							, t.[SQL Mail XPs]					   	= s.[SQL Mail XPs]
							, t.[transform noise words]			   	= s.[transform noise words]
							, t.[two digit year cutoff]			   	= s.[two digit year cutoff]
							, t.[user connections]				   	= s.[user connections]
							, t.[user options]					   	= s.[user options]
							, t.[xp_cmdshell]						= s.[xp_cmdshell]
							, t.[trace_flags_enabled]				= s.[trace_flags_enabled]
							, t.[DataCollectionTime]				= s.[DataCollectionTime]

					WHEN NOT MATCHED BY SOURCE AND t.server_name NOT IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor]) THEN 
						DELETE				
					OUTPUT $action AS [Action], deleted.*) AS History
				WHERE [Action] IN ('UPDATE', 'DELETE');

		MERGE dbo.ServerConfigurations_History AS t
			USING #h AS s
				ON s.server_name = t.server_name
					AND s.RowCheckSum = t.RowCheckSum
			WHEN NOT MATCHED THEN
				INSERT ([Action],[server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
						,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
						,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
						,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
						,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)],[ft crawl bandwidth (max)]
						,[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)],[in-doubt xact resolution]
						,[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)],[max text repl size (B)]
						,[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers],[network packet size (B)]
						,[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank],[priority boost]
						,[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections],[remote login timeout (s)]
						,[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion],[set working set size]
						,[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections],[user options]
						,[xp_cmdshell],[trace_flags_enabled],[BackupRootPath],[LogFilesRootPath],[KeepNBackups],[DataCollectionTime],[RowCheckSum])
		
				VALUES ([Action],[server_name],[access check cache bucket count],[access check cache quota],[Ad Hoc Distributed Queries],[affinity I/O mask],[affinity mask]
						,[affinity64 I/O mask],[affinity64 mask],[Agent XPs],[allow updates],[awe enabled],[backup checksum default],[backup compression default]
						,[blocked process threshold (s)],[c2 audit mode],[clr enabled],[common criteria compliance enabled],[contained database authentication]
						,[cost threshold for parallelism],[cross db ownership chaining],[cursor threshold],[Database Mail XPs],[default full-text language],[default language]
						,[default trace enabled],[disallow results from triggers],[EKM provider enabled],[filestream access level],[fill factor (%)],[ft crawl bandwidth (max)]
						,[ft crawl bandwidth (min)],[ft notify bandwidth (max)],[ft notify bandwidth (min)],[index create memory (KB)],[in-doubt xact resolution]
						,[lightweight pooling],[locks],[max degree of parallelism],[max full-text crawl range],[max server memory (MB)],[max text repl size (B)]
						,[max worker threads],[media retention],[min memory per query (KB)],[min server memory (MB)],[nested triggers],[network packet size (B)]
						,[Ole Automation Procedures],[open objects],[optimize for ad hoc workloads],[PH timeout (s)],[precompute rank],[priority boost]
						,[query governor cost limit],[query wait (s)],[recovery interval (min)],[remote access],[remote admin connections],[remote login timeout (s)]
						,[remote proc trans],[remote query timeout (s)],[Replication XPs],[scan for startup procs],[server trigger recursion],[set working set size]
						,[show advanced options],[SMO and DMO XPs],[SQL Mail XPs],[transform noise words],[two digit year cutoff],[user connections],[user options]
						,[xp_cmdshell],[trace_flags_enabled],[BackupRootPath],[LogFilesRootPath],[KeepNBackups],[DataCollectionTime],[RowCheckSum]);
					
		TRUNCATE TABLE dbo.ServerConfigurations_Loading;

		COMMIT;

		-- This query will return the differences between the new and old records.
		SET @SQLtableHTML = 'SET @tableHTML = (SELECT CONVERT(VARCHAR(MAX), ''<tr><td class="h">[server_name]</td><td class="h" colspan="2">'' + ISNULL(CONVERT(VARCHAR(256), del.server_name), '''') + ''</td>''';

		SET @SQLtableHTML += ( SELECT ' + CASE WHEN ISNULL(CONVERT(VARCHAR(256),ins.'+ QUOTENAME(name) +'),'''') <> ISNULL(CONVERT(VARCHAR(256),del.'+ QUOTENAME(name) +'),'''') THEN ''<tr><td>' 
										+  name 
										+ '</td><td class="d">'' + ISNULL(CONVERT(VARCHAR(256), del.' 
										+ QUOTENAME(name) + '), '''') + ''</td><td class="i">'' + ISNULL(CONVERT(VARCHAR(256), ins.'
										+ QUOTENAME(name) + '), '''') + ''</td></tr>'' ELSE '''' END' + CHAR(10)
									FROM sys.columns
									WHERE object_id = OBJECT_ID('dbo.ServerConfigurations')
										AND name NOT IN ('ID', 'server_name', 'RowCheckSum')
									ORDER BY column_id 
									FOR XML PATH(''))
						
		SET @SQLtableHTML += ')
					FROM #h	AS del	
						INNER JOIN dbo.ServerConfigurations AS ins
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
						INNER JOIN dbo.ServerConfigurations AS ins
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
