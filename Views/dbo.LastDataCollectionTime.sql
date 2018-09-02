SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[LastDataCollectionTime]
AS 

		  SELECT '[dbo].[DatabaseInformation]' AS TableInformation, MIN(DataCollectionTime) AS DataCollectionTime	FROM [dbo].[DatabaseInformation]
UNION ALL SELECT '[dbo].[DatabaseSizeInformation]',					MIN(DataCollectionTime)							FROM [dbo].[DatabaseSizeInformation]
UNION ALL SELECT '[dbo].[ServerConfigurations]',					MIN(DataCollectionTime)							FROM [dbo].[ServerConfigurations]
UNION ALL SELECT '[dbo].[ServerDisksInformation]',					MIN(DataCollectionTime)							FROM [dbo].[ServerDisksInformation]
UNION ALL SELECT '[dbo].[ServerInformation]',						MIN(DataCollectionTime)							FROM [dbo].[ServerInformation]
UNION ALL SELECT '[dbo].[ServerProperties]',						MIN(DataCollectionTime)							FROM [dbo].[ServerProperties]
GO
