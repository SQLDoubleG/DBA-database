CREATE TABLE [dbo].[ServerDisksInformation_History]
(
[ID] [int] NOT NULL IDENTITY(1, 1),
[Action] [sys].[sysname] NOT NULL,
[server_name] [sys].[sysname] NOT NULL,
[Drive] [char] (2) COLLATE Latin1_General_CI_AS NOT NULL,
[VolName] [sys].[sysname] NULL,
[FileSystem] [nvarchar] (16) COLLATE Latin1_General_CI_AS NULL,
[SizeMB] [int] NULL,
[FreeMB] [int] NULL,
[ClusterSize] [int] NULL,
[SizeGB] AS (CONVERT([decimal](10,2),[SizeMB]/(1024.),(0))),
[FreeGB] AS (CONVERT([decimal](10,2),[FreeMB]/(1024.),(0))),
[FreePercent] AS (CONVERT([decimal](4,1),((100.0)*[FreeMB])/[SizeMB],(0))),
[Message] AS (case  when CONVERT([decimal](4,1),((100.0)*[FreeMB])/[SizeMB],(0))<(10.0) then 'Alarm!!!' when CONVERT([decimal](4,1),((100.0)*[FreeMB])/[SizeMB],(0))<(20.0) then 'Warning!!!' else '' end),
[DataCollectionTime] [datetime] NULL,
[RowCheckSum] [int] NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ServerDisksInformation_History] ADD CONSTRAINT [PK_ServerDisksInformation_History] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
