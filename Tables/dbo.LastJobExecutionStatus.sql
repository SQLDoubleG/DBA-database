CREATE TABLE [dbo].[LastJobExecutionStatus]
(
[server_name] [sys].[sysname] NOT NULL,
[job_id] [uniqueidentifier] NULL,
[job_name] [sys].[sysname] NULL,
[step_id] [int] NULL,
[step_name] [sys].[sysname] NULL,
[enabled] [varchar] (3) COLLATE Latin1_General_CI_AS NULL,
[owner_name] [sys].[sysname] NULL,
[job_schedule] [nvarchar] (max) COLLATE Latin1_General_CI_AS NULL,
[next_run] [varchar] (20) COLLATE Latin1_General_CI_AS NULL,
[last_run] [varchar] (20) COLLATE Latin1_General_CI_AS NULL,
[last_run_status] [varchar] (30) COLLATE Latin1_General_CI_AS NULL,
[last_run_duration] [varchar] (24) COLLATE Latin1_General_CI_AS NULL,
[DataCollectionTime] [datetime2] (2) NULL CONSTRAINT [DF_LastJobExecutionStatus_DataCollectionTime] DEFAULT (getdate())
) ON [PRIMARY]
GO
