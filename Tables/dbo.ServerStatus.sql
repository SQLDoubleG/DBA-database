CREATE TABLE [dbo].[ServerStatus]
(
[server_name] [sys].[sysname] NOT NULL,
[DisplayName] [sys].[sysname] NOT NULL,
[Name] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[State] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[Status] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[StartMode] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[StartName] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[DateCollectionTime] [datetime2] (3) NULL,
[RowCheckSum] [int] NULL
) ON [PRIMARY]
GO
