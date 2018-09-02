CREATE TABLE [dbo].[ServerInformation]
(
[ID] [int] NOT NULL IDENTITY(1, 1) NOT FOR REPLICATION,
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
[DataCollectionTime] [datetime] NOT NULL,
[isAccessible] [bit] NULL,
[power_plan] [nvarchar] (20) COLLATE Latin1_General_CI_AS NULL,
[RowCheckSum] AS (checksum([server_name],[OS],[OSArchitecture],[OSPatchLevel],[OSVersion],[LastBootUpTime],[TotalVisibleMemorySize],[TotalPhysicalMemorySize],[TotalMemoryModules],[IPAddress],[physical_cpu_count],[cores_per_cpu],[logical_cpu_count],[manufacturer],[server_model],[processor_name],[isAccessible],[power_plan]))
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[ServerInformation] ADD CONSTRAINT [PK_ServerInformation] PRIMARY KEY CLUSTERED  ([ID]) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UIX_ServerInformation_server_name] ON [dbo].[ServerInformation] ([server_name]) ON [PRIMARY]
GO
GRANT SELECT ON  [dbo].[ServerInformation] TO [reporting]
GO
