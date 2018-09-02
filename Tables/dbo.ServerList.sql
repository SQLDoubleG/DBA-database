CREATE TABLE [dbo].[ServerList]
(
[ID] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [sys].[sysname] NOT NULL,
[server_ip_address] [varchar] (30) COLLATE Latin1_General_CI_AS NULL,
[MonitoringActive] [bit] NOT NULL CONSTRAINT [ServerList_MonitoringActive_df] DEFAULT ((1)),
[Notes] [nvarchar] (1000) COLLATE Latin1_General_CI_AS NULL,
[isSQLServer] [bit] NULL CONSTRAINT [DF__ServerLis__isSQL__32E0915F] DEFAULT ((1)),
[isProduction] [bit] NULL,
[isDBAreplicated] [bit] NULL,
[DBAreplicationType] [nvarchar] (128) COLLATE Latin1_General_CI_AS NULL,
[adminLogin] [sys].[sysname] NULL,
[adminPassword] [varbinary] (128) NULL,
[monitoringLogin] [sys].[sysname] NULL,
[monitoringPassword] [varbinary] (128) NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ServerList] ADD CONSTRAINT [PK_ServerList] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [UIX_ServerList_server_name] ON [dbo].[ServerList] ([server_name]) ON [PRIMARY]
GO
