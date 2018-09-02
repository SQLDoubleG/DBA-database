CREATE TABLE [dbo].[ServerStatus_Loading]
(
[server_name] [sys].[sysname] NOT NULL,
[DisplayName] [sys].[sysname] NOT NULL,
[Name] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[State] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[Status] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[StartMode] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[StartName] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[DateCollectionTime] [datetime2] (3) NULL CONSTRAINT [DF_ServerStatus_Loading_DateCollectionTime] DEFAULT (getdate()),
[RowCheckSum] AS (checksum([server_name],[DisplayName],[Name],[State],[Status],[StartMode],[StartName]))
) ON [PRIMARY]
GO
