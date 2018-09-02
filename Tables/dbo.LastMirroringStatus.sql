CREATE TABLE [dbo].[LastMirroringStatus]
(
[DatabaseName] [sys].[sysname] NOT NULL,
[mirroring_role] [int] NULL,
[mirroring_role_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NOT NULL,
[mirroring_state] [int] NULL,
[mirroring_state_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NOT NULL,
[mirroring_witness_state] [int] NULL,
[mirroring_witness_state_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NOT NULL,
[mirroring_change_date] [datetime] NOT NULL CONSTRAINT [DF_LastMirroringStatus_mirroring_change_date] DEFAULT (getdate()),
[mirroring_safety_level] [int] NULL,
[mirroring_safety_level_desc] [nvarchar] (60) COLLATE Latin1_General_CI_AS NULL,
[server_name] [sys].[sysname] NOT NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[LastMirroringStatus] ADD CONSTRAINT [PK_LastMirroringStatus] PRIMARY KEY CLUSTERED  ([server_name], [DatabaseName]) ON [PRIMARY]
GO
