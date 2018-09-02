SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_ServerProperties]
AS
SELECT [server_name]
		,[BackupDirectory]
		,[BuildClrVersion]
		,[Collation]
		,[CollationID]
		,[ComparisonStyle]
		,[ComputerNamePhysicalNetBIOS]
		,[Edition]
		,[EditionID]
		,[EngineEdition]
		,[FilestreamConfiguredLevel]
		,[FilestreamEffectiveLevel]
		,[FilestreamShareName]
		,[HadrManagerStatus]
		,[InstanceDefaultDataPath]
		,[InstanceDefaultLogPath]
		,[InstanceName]
		,[IsClustered]
		,[IsFullTextInstalled]
		,[IsHadrEnabled]
		,[IsIntegratedSecurityOnly]
		,[IsLocalDB]
		,[IsSingleUser]
		,[IsXTPSupported]
		,[LCID]
		,[LicenseType]
		,[MachineName]
		,[NumLicenses]
		,[ProcessID]
		,[ProductLevel]
		,[ProductVersion]
		,[ResourceLastUpdateDateTime]
		,[ResourceVersion]
		,[ServerName]
		,[SqlCharSet]
		,[SqlCharSetName]
		,[SqlSortOrder]
		,[SqlSortOrderName]
		,[DataCollectionTime]
	FROM [DBA].[dbo].[ServerProperties]
	WHERE server_name = @@SERVERNAME



GO
