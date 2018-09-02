SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[vServersToMonitor]
AS
	
SELECT	DISTINCT LEFT(server_name, CASE CHARINDEX('\', server_name, 1) WHEN 0 THEN LEN(server_name) ELSE CHARINDEX('\', server_name, 1) -1 END) AS MachineName
	FROM dbo.ServerList 
	WHERE MonitoringActive = 1

GO
