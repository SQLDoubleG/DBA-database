CREATE TABLE [dbo].[DBCC_History]
(
[ID] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
[server_name] [sys].[sysname] NOT NULL,
[name] [sys].[sysname] NOT NULL,
[DBCC_datetime] [datetime2] (0) NULL,
[DBCC_duration] [varchar] (24) COLLATE Latin1_General_CI_AS NULL,
[isPhysicalOnly] [bit] NULL,
[isDataPurity] [bit] NULL,
[ErrorNumber] [int] NULL,
[command] [varchar] (20) COLLATE Latin1_General_CI_AS NOT NULL CONSTRAINT [DF_DBCC_History_command_CHECKDB] DEFAULT ('CHECKDB')
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[DBCC_History] ADD CONSTRAINT [PK_DBCC_History] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
