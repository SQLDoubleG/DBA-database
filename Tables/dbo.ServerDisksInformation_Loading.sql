CREATE TABLE [dbo].[ServerDisksInformation_Loading]
(
[server_name] [sys].[sysname] NOT NULL,
[Drive] [varchar] (2) COLLATE Latin1_General_CI_AS NULL,
[VolName] [sys].[sysname] NULL,
[FileSystem] [nvarchar] (16) COLLATE Latin1_General_CI_AS NULL,
[SizeMB] [int] NULL,
[FreeMB] [int] NULL,
[ClusterSize] [int] NULL,
[DataCollectionTime] [datetime] NULL
) ON [PRIMARY]
GO
