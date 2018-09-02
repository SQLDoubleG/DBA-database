CREATE TABLE [dbo].[StatsMaintenanceHistory]
(
[Id] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [sys].[sysname] NOT NULL,
[database_id] [int] NOT NULL,
[database_name] [sys].[sysname] NOT NULL,
[object_id] [int] NOT NULL,
[schema_name] [sys].[sysname] NOT NULL,
[object_name] [sys].[sysname] NOT NULL,
[stats_id] [int] NOT NULL,
[stats_name] [sys].[sysname] NOT NULL,
[auto_created] [bit] NOT NULL,
[table_row_count] [int] NOT NULL,
[stats_row_count] [int] NOT NULL,
[stats_last_updated] [datetime2] (3) NOT NULL,
[rows_sampled] [int] NOT NULL,
[percentage_sampled] [decimal] (19, 2) NOT NULL,
[real_percentage_sampled] [decimal] (19, 2) NOT NULL,
[stats_modification_counter] [int] NOT NULL,
[stats_modification_percentage] [decimal] (19, 2) NOT NULL,
[DataCollectionTime] [datetime2] (3) NOT NULL,
[Duration_seconds] [int] NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[StatsMaintenanceHistory] ADD CONSTRAINT [PK_StatsMaintenanceHistory] PRIMARY KEY CLUSTERED  ([Id]) ON [PRIMARY]
GO
