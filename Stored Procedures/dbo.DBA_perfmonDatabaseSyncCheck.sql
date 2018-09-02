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
-- Create date: 26/03/2018
-- Description:	Send an email when performance databases get out of sync for longer than 3 hours
--				This sp will be called from a SQL Agent Job in a regular schedule
--
-- Change Log:	
--				08/05/2018	RAG	Added validation for servers to be still active by joinin to the output of [DBA_getServersToMonitor]
--				18/05/2018	RAG	Fix: Join to MachineName not to ServerName to account for servers with only named instances.
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_perfmonDatabaseSyncCheck]
AS 
BEGIN
DECLARE @tableHTML		NVARCHAR(MAX) = '';
DECLARE @HTML			NVARCHAR(MAX);
DECLARE @emailSubject	NVARCHAR(128) = 'Perfmon Databases out of sync';

DECLARE @SQL NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#temptable') IS NOT NULL DROP TABLE #temptable;

CREATE TABLE #temptable (
	[database_name]		 sysname	  NOT NULL
  , [LastDataCollection] DATETIME2(3) NOT NULL
);

CREATE TABLE #servers (
	[ServerName]	 sysname NOT NULL
  , [MachineName]	 sysname NOT NULL
  , [remoteLogin]	 sysname NOT NULL
  , [remotePassword] sysname NOT NULL
);

INSERT INTO #servers (ServerName, MachineName, remoteLogin, remotePassword)
EXECUTE DBA.dbo.DBA_getServersToMonitor @onePerMachine = 1, @isAdmin = 0, @server_name = NULL

SET @SQL = (SELECT STUFF(
						(SELECT 'UNION ALL SELECT ''' + name  + ''', MAX(CounterDateTime) FROM ' + name +  '.dbo.Parsed' + CHAR(10)
							FROM sys.databases AS d
							INNER JOIN #servers AS s
								ON s.MachineName = SUBSTRING(d.name, CHARINDEX('_', d.name) + 1 , LEN(d.name) - CHARINDEX('_', d.name))
							WHERE d.name LIKE 'perfmon%'
							FOR XML PATH('')), 1,10, ''));

INSERT INTO #temptable (database_name, LastDataCollection)
	EXEC sys.sp_executesql @stmt = @SQL;

IF EXISTS (SELECT 1 FROM #temptable WHERE LastDataCollection < DATEADD(HOUR, -3, GETDATE())) BEGIN

	SET @tableHTML = (SELECT '<tr><td>' + [database_name] + '</td><td>' + CONVERT(VARCHAR(30), [LastDataCollection]) + '</td></tr>'
						FROM #temptable WHERE LastDataCollection < DATEADD(HOUR, -3, GETDATE())
						FOR XML PATH(''));

	SET @tableHTML = REPLACE(REPLACE(@tableHTML, '&lt;', '<'), '&gt;', '>');


	SET @HTML = N'<html><head><style type="text/css">.ac{text-align:center}.diff {color:red} th{background-color:#5B9BD5;color:white;font-weight:bold;width:250px} td {white-space:nowrap;} .i{color:green;} .d{color:red;} .h{background-color:lightblue;font-weight:bold;}</style></head><body>'
						+ N'<table border="1">'
						+ N'<tr class="ac">'
						+ N'<th>Database Name</th>' 						
						+ N'<th>Last Data Collection Time</th></tr>'
						+ @tableHTML
						+ '</table>'
						+ '</body></html>';

	EXEC msdb.dbo.sp_send_dbmail @profile_name = 'Admin Profile'
		, @recipients = 'DatabaseAdministrators@rws.com'
		, @subject = @emailSubject
		, @body = @HTML
		, @body_format = 'HTML';
END;

END;

GO
