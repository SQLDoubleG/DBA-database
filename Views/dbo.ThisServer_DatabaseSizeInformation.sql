SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_DatabaseSizeInformation]
AS
SELECT [server_name]
		,[name]
		,[Size_MB]
		,[SpaceAvailable_MB]
		,[DataSpace_MB]
		,[IndexSpace_MB]
		,[LogSpace_MB]
		,[Size_GB]
		,[SpaceAvailable_GB]
		,[DataSpace_GB]
		,[IndexSpace_GB]
		,[LogSpace_GB]
		,[DataCollectionTime]
	FROM [dbo].[DatabaseSizeInformation]
	WHERE server_name = @@SERVERNAME



GO
