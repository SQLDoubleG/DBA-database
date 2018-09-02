SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_All_ServerDisksInformation]
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
	FROM [dbo].[ServerDisksInformation]
	WHERE server_name = @@SERVERNAME
UNION
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
	FROM [dbo].[ServerDisksInformation_History]
	WHERE server_name = @@SERVERNAME
GO
