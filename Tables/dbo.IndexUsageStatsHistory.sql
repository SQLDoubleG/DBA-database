CREATE TABLE [dbo].[IndexUsageStatsHistory]
(
[Id] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [sys].[sysname] NOT NULL,
[database_id] [sys].[sysname] NOT NULL,
[database_name] [sys].[sysname] NOT NULL,
[schema_name] [sys].[sysname] NOT NULL,
[object_id] [int] NOT NULL,
[object_name] [sys].[sysname] NOT NULL,
[index_id] [int] NOT NULL,
[index_name] [sys].[sysname] NULL,
[total_user_seeks] [bigint] NOT NULL,
[total_user_scans] [bigint] NOT NULL,
[total_user_lookups] [bigint] NOT NULL,
[total_user_updates] [bigint] NOT NULL,
[user_seeks] [bigint] NOT NULL,
[user_scans] [bigint] NOT NULL,
[user_lookups] [bigint] NOT NULL,
[user_updates] [bigint] NOT NULL,
[last_user_seek] [datetime] NULL,
[last_user_scan] [datetime] NULL,
[last_user_lookup] [datetime] NULL,
[last_user_update] [datetime] NULL,
[total_system_seeks] [bigint] NOT NULL,
[total_system_scans] [bigint] NOT NULL,
[total_system_lookups] [bigint] NOT NULL,
[total_system_updates] [bigint] NOT NULL,
[system_seeks] [bigint] NOT NULL,
[system_scans] [bigint] NOT NULL,
[system_lookups] [bigint] NOT NULL,
[system_updates] [bigint] NOT NULL,
[last_system_seek] [datetime] NULL,
[last_system_scan] [datetime] NULL,
[last_system_lookup] [datetime] NULL,
[last_system_update] [datetime] NULL,
[created_date] [datetime2] (2) NOT NULL CONSTRAINT [DF_IndexUsageStatsHistory_created_date] DEFAULT (getdate()),
[modified_date] [datetime2] (2) NOT NULL CONSTRAINT [DF_IndexUsageStatsHistory_modified_date] DEFAULT (getdate())
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[IndexUsageStatsHistory] ADD CONSTRAINT [PK_IndexUsageStatsHistory] PRIMARY KEY CLUSTERED  ([Id]) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_IndexUsageStatsHistory_merge] ON [dbo].[IndexUsageStatsHistory] ([server_name], [database_name], [object_id], [index_id]) INCLUDE ([index_name]) ON [PRIMARY]
GO
