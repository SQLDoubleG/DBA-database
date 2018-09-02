CREATE TABLE [dbo].[ServerInformation_Loading]
(
[server_name] [sys].[sysname] NOT NULL,
[OS] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[OSArchitecture] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[OSPatchLevel] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[OSVersion] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[LastBootUpTime] [datetime] NULL,
[TotalVisibleMemorySize] [int] NULL,
[TotalPhysicalMemorySize] [int] NULL,
[TotalMemoryModules] [int] NULL,
[IPAddress] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[physical_cpu_count] [int] NULL,
[cores_per_cpu] [int] NULL,
[logical_cpu_count] [int] NULL,
[manufacturer] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[server_model] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[processor_name] [nvarchar] (255) COLLATE Latin1_General_CI_AS NULL,
[DataCollectionTime] [datetime] NULL,
[power_plan] [nvarchar] (20) COLLATE Latin1_General_CI_AS NULL
) ON [PRIMARY]
GO
