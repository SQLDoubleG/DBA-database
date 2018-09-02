SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO



CREATE VIEW [dbo].[vSQLServersToMonitor]
AS

SELECT	server_name
		, server_ip_address
		, LEFT(server_name, CASE CHARINDEX('\', server_name, 1) WHEN 0 THEN LEN(server_name) ELSE CHARINDEX('\', server_name, 1) -1 END) AS MachineName
		, CASE WHEN CHARINDEX('\', server_name, 1) = 0 THEN 'default' ELSE RIGHT(server_name, LEN(server_name)-CHARINDEX('\', server_name, 1)) END AS InstanceName
	FROM dbo.ServerList 
	WHERE MonitoringActive = 1
		AND isSQLServer = 1



GO
