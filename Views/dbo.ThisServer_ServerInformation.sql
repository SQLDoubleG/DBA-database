SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_ServerInformation]
AS
SELECT	[server_name]
		,[OS]
		,[OSArchitecture]
		,[OSPatchLevel]
		,[OSVersion]
		,[LastBootUpTime]
		,[TotalVisibleMemorySize]
		,[TotalPhysicalMemorySize]
		,[TotalMemoryModules]
		,[IPAddress]
		,[physical_cpu_count]
		,[cores_per_cpu]
		,[logical_cpu_count]
		,[server_model]
		,[processor_name]
		,[DataCollectionTime]
		,[isAccessible]
	FROM [DBA].[dbo].[ServerInformation]
	WHERE server_name = @@SERVERNAME




GO
