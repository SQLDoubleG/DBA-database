CREATE TABLE [dbo].[ServerAudit]
(
[ID] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [sys].[sysname] NULL,
[EventType] [sys].[sysname] NULL,
[PostTime] [datetime2] (3) NULL,
[LoginName] [sys].[sysname] NULL,
[ObjectName] [sys].[sysname] NULL,
[ObjectType] [sys].[sysname] NULL,
[CommandText] [nvarchar] (max) COLLATE Latin1_General_CI_AS NULL,
[eventdata] [xml] NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ServerAudit] ADD CONSTRAINT [PK_ServerAudit] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
