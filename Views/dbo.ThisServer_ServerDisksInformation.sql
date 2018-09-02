SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_ServerDisksInformation]
AS

SELECT [server_name]
		,[Drive]
		,[VolName]
		,[FileSystem]
		,[SizeMB]
		,[FreeMB]
		,[SizeGB]
		,[FreeGB]
		,[FreePercent]
		,[Message]
		,[DataCollectionTime]
	FROM [DBA].[dbo].[ServerDisksInformation]
	WHERE server_name = CONVERT(SYSNAME, SERVERPROPERTY('MachineName'))



GO
