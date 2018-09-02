CREATE TABLE [dbo].[IndexFragmentationHistory]
(
[Id] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[Action] [varchar] (15) COLLATE Latin1_General_CI_AS NOT NULL,
[isOnlineOperation] [bit] NOT NULL,
[server_name] [sys].[sysname] NOT NULL,
[database_name] [sys].[sysname] NOT NULL,
[database_id] [int] NOT NULL,
[object_id] [int] NOT NULL,
[schema_name] [sys].[sysname] NOT NULL,
[object_name] [sys].[sysname] NOT NULL,
[index_id] [int] NOT NULL,
[partition_number] [int] NOT NULL,
[partition_count] [int] NOT NULL,
[ignore_dup_key] [bit] NOT NULL,
[is_padded] [bit] NOT NULL,
[fill_factor] [int] NOT NULL,
[data_compression_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[avg_fragmentation_in_percent] [float] NOT NULL,
[page_count] [bigint] NOT NULL,
[index_name] [sys].[sysname] NOT NULL,
[type] [tinyint] NOT NULL,
[type_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[is_primary_key] [bit] NULL,
[IsView] [int] NULL,
[IsIndexed] [int] NULL,
[ExecIsAnsiNullsOn] [int] NULL,
[allow_row_locks] [bit] NULL,
[allow_page_locks] [bit] NULL,
[HasLobData] [int] NOT NULL,
[DataCollectionTime] [datetime] NOT NULL,
[Duration_seconds] [int] NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[IndexFragmentationHistory] ADD CONSTRAINT [PK_IndexFragmentationHistory] PRIMARY KEY CLUSTERED  ([Id]) ON [PRIMARY]
GO
