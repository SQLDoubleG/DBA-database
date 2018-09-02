CREATE TABLE [dbo].[DatabaseSizeInformation]
(
[ID] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [nvarchar] (128) COLLATE Latin1_General_CI_AS NOT NULL,
[name] [nvarchar] (128) COLLATE Latin1_General_CI_AS NOT NULL,
[DataCollectionTime] [datetime] NOT NULL,
[Size_MB] [decimal] (10, 2) NULL,
[SpaceAvailable_MB] [decimal] (10, 2) NULL,
[DataSpace_MB] [decimal] (10, 2) NULL,
[IndexSpace_MB] [decimal] (10, 2) NULL,
[LogSpace_MB] [decimal] (10, 2) NULL,
[Size_GB] AS (CONVERT([decimal](10,2),[Size_MB]/(1024),(0))),
[SpaceAvailable_GB] AS (CONVERT([decimal](10,2),[SpaceAvailable_MB]/(1024),(0))),
[DataSpace_GB] AS (CONVERT([decimal](10,2),[DataSpace_MB]/(1024),(0))),
[IndexSpace_GB] AS (CONVERT([decimal](10,2),[IndexSpace_MB]/(1024),(0))),
[LogSpace_GB] AS (CONVERT([decimal](10,2),[LogSpace_MB]/(1024),(0))),
[RowCheckSum] [int] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[DatabaseSizeInformation] ADD CONSTRAINT [PK_DatabaseSizeInformation] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
