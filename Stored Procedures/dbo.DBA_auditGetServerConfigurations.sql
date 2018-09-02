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
-- Create date: 10/02/2015
-- Description:	Gets Instance Properties
--
-- Parameters:	
--				@insertAuditTables, will insert the table [DBA].[dbo].[ServerConfigurations_Loading]
--
-- Assumptions:	This SP uses relies on the table sys.configurations, retrieving all values from version 2005 onwards.
--				19/03/2015 RAG - TRUSTWORTHY must be ON for [DBA] database and [sa] the owner as on remote servers, it will execute as 'dbo'
--								DO NOT ADD MEMBERS TO THE [db_owner] database role as that can compromise the security of the server
--
-- Change Log:	
--				19/03/2015 RAG - Added WITH EXECUTE AS 'dbo' due to lack of permissions on remote servers
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditGetServerConfigurations]
WITH EXECUTE AS 'dbo'
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @traceStatus TABLE(
		[TraceFlag]	INT
		, [Status]	BIT
		, [Global]	BIT
		, [Session]	BIT
	)

	-- Get info for trace flags
	INSERT INTO @traceStatus
	EXECUTE sp_executesql N'DBCC TRACESTATUS(-1)'

	-- Get one row from all cofig values to match the structure of the loading table
	SELECT	CONVERT(SYSNAME, SERVERPROPERTY('ServerName')) AS [server_name]
			, PVT.[access check cache bucket count]
			, PVT.[access check cache quota]
			, PVT.[Ad Hoc Distributed Queries]
			, PVT.[affinity I/O mask]
			, PVT.[affinity mask]
			, PVT.[affinity64 I/O mask]
			, PVT.[affinity64 mask]
			, PVT.[Agent XPs]
			, PVT.[allow updates]
			, PVT.[awe enabled]
			, PVT.[backup checksum default]
			, PVT.[backup compression default]
			, PVT.[blocked process threshold (s)]
			, PVT.[c2 audit mode]
			, PVT.[clr enabled]
			, PVT.[common criteria compliance enabled]
			, PVT.[contained database authentication]
			, PVT.[cost threshold for parallelism]
			, PVT.[cross db ownership chaining]
			, PVT.[cursor threshold]
			, PVT.[Database Mail XPs]
			, PVT.[default full-text language]
			, PVT.[default language]
			, PVT.[default trace enabled]
			, PVT.[disallow results from triggers]
			, PVT.[EKM provider enabled]
			, PVT.[filestream access level]
			, PVT.[fill factor (%)]
			, PVT.[ft crawl bandwidth (max)]
			, PVT.[ft crawl bandwidth (min)]
			, PVT.[ft notify bandwidth (max)]
			, PVT.[ft notify bandwidth (min)]
			, PVT.[index create memory (KB)]
			, PVT.[in-doubt xact resolution]
			, PVT.[lightweight pooling]
			, PVT.[locks]
			, PVT.[max degree of parallelism]
			, PVT.[max full-text crawl range]
			, PVT.[max server memory (MB)]
			, PVT.[max text repl size (B)]
			, PVT.[max worker threads]
			, PVT.[media retention]
			, PVT.[min memory per query (KB)]
			, PVT.[min server memory (MB)]
			, PVT.[nested triggers]
			, PVT.[network packet size (B)]
			, PVT.[Ole Automation Procedures]
			, PVT.[open objects]
			, PVT.[optimize for ad hoc workloads]
			, PVT.[PH timeout (s)]
			, PVT.[precompute rank]
			, PVT.[priority boost]
			, PVT.[query governor cost limit]
			, PVT.[query wait (s)]
			, PVT.[recovery interval (min)]
			, PVT.[remote access]
			, PVT.[remote admin connections]
			, PVT.[remote login timeout (s)]
			, PVT.[remote proc trans]
			, PVT.[remote query timeout (s)]
			, PVT.[Replication XPs]
			, PVT.[scan for startup procs]
			, PVT.[server trigger recursion]
			, PVT.[set working set size]
			, PVT.[show advanced options]
			, PVT.[SMO and DMO XPs]
			, PVT.[SQL Mail XPs]
			, PVT.[transform noise words]
			, PVT.[two digit year cutoff]
			, PVT.[user connections]
			, PVT.[user options]
			, PVT.[xp_cmdshell]
			, STUFF((SELECT ', ' + CONVERT(VARCHAR,[TraceFlag])
						FROM @traceStatus
						WHERE [Status] = 1
							AND [Global] = 1
						FOR XML PATH('')), 1,2,'') AS [trace_flags_enabled]
			, GETDATE() AS [DataCollectionTime]
--		INTO #source
		FROM (
			SELECT name
					, value_in_use
				FROM sys.configurations) AS t
			PIVOT
				(MAX(value_in_use)
					FOR name IN ( [access check cache bucket count], [access check cache quota], [Ad Hoc Distributed Queries], [affinity I/O mask], [affinity mask]
								, [affinity64 I/O mask], [affinity64 mask], [Agent XPs], [allow updates], [awe enabled], [backup checksum default], [backup compression default]
								, [blocked process threshold (s)], [c2 audit mode], [clr enabled], [common criteria compliance enabled], [contained database authentication]
								, [cost threshold for parallelism], [cross db ownership chaining], [cursor threshold], [Database Mail XPs], [default full-text language]
								, [default language], [default trace enabled], [disallow results from triggers], [EKM provider enabled], [filestream access level]
								, [fill factor (%)], [ft crawl bandwidth (max)], [ft crawl bandwidth (min)], [ft notify bandwidth (max)], [ft notify bandwidth (min)]
								, [index create memory (KB)], [in-doubt xact resolution], [lightweight pooling], [locks], [max degree of parallelism], [max full-text crawl range]
								, [max server memory (MB)], [max text repl size (B)], [max worker threads], [media retention], [min memory per query (KB)], [min server memory (MB)]
								, [nested triggers], [network packet size (B)], [Ole Automation Procedures], [open objects], [optimize for ad hoc workloads], [PH timeout (s)]
								, [precompute rank], [priority boost], [query governor cost limit], [query wait (s)], [recovery interval (min)], [remote access]
								, [remote admin connections], [remote login timeout (s)], [remote proc trans], [remote query timeout (s)], [Replication XPs]
								, [scan for startup procs], [server trigger recursion], [set working set size], [show advanced options], [SMO and DMO XPs], [SQL Mail XPs]
								, [transform noise words], [two digit year cutoff], [user connections], [user options], [xp_cmdshell])
				) AS PVT	
	
END





GO
GRANT EXECUTE ON  [dbo].[DBA_auditGetServerConfigurations] TO [dbaMonitoringUser]
GO
