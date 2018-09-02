SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2018 Raul Gonzalez, @SQLDoubleG
-- All rights reserved.
--   
-- You may alter this code for your own *non-commercial* purposes. You may
-- republish altered code as long as you give due credit.
--   
-- THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
-- ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
-- TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
-- PARTICULAR PURPOSE.
--
-- =============================================
-- Author:		Raul Gonzalez
-- Create date: 10/02/2015
-- Description:	Gets Server Properties
--
-- Parameters:	
--
-- Assumptions:	This SP uses relies on the function SERVERPROPERTY, retrieving values for version 2005 onwards. 
--				Including InstanceDefaultDataPath, InstanceDefaultLogPath and BackupDirectory (from registry)
--				19/03/2015 RAG - TRUSTWORTHY must be ON for [DBA] database and [sa] the owner as on remote servers, it will execute as 'dbo'
--								DO NOT ADD MEMBERS TO THE [db_owner] database role as that can compromise the security of the server
--
-- Change Log:	
--				19/03/2015 RAG - Added WITH EXECUTE AS 'dbo' due to lack of permissions on remote servers
--				19/07/2016 SZO - Removed partial comment from "Assumptions" as InstanceDefaultLogPath is present in BOL.
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditGetServerProperties]
WITH EXECUTE AS 'dbo'
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @DefaultData		SQL_VARIANT
	DECLARE @DefaultLog			SQL_VARIANT
	DECLARE @BackupDirectory	SQL_VARIANT

	IF dbo.[getNumericSQLVersion](CONVERT(SYSNAME, SERVERPROPERTY('ProductVersion'))) >= 11 BEGIN
		SET @DefaultData	= CONVERT(SYSNAME, (SELECT SERVERPROPERTY('InstanceDefaultDataPath')) )
		SET @DefaultLog		= CONVERT(SYSNAME, (SELECT SERVERPROPERTY('InstanceDefaultLogPath')) )
	END
	ELSE BEGIN
		EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData',	@DefaultData			OUTPUT
		EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog',	@DefaultLog				OUTPUT
	END 

    EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer',	N'BackupDirectory', @BackupDirectory		OUTPUT    

	SELECT CONVERT(SYSNAME, SERVERPROPERTY('ServerName')) AS server_name
			, @BackupDirectory AS BackupDirectory
			, SERVERPROPERTY('BuildClrVersion') AS BuildClrVersion
			, SERVERPROPERTY('Collation') AS Collation
			, SERVERPROPERTY('CollationID') AS CollationID
			, SERVERPROPERTY('ComparisonStyle') AS ComparisonStyle
			, SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS ComputerNamePhysicalNetBIOS
			, SERVERPROPERTY('Edition') AS Edition
			, SERVERPROPERTY('EditionID') AS EditionID
			, SERVERPROPERTY('EngineEdition') AS EngineEdition
			, SERVERPROPERTY('FilestreamConfiguredLevel') AS FilestreamConfiguredLevel
			, SERVERPROPERTY('FilestreamEffectiveLevel') AS FilestreamEffectiveLevel
			, SERVERPROPERTY('FilestreamShareName') AS FilestreamShareName
			, SERVERPROPERTY('HadrManagerStatus') AS HadrManagerStatus
			, @DefaultData AS InstanceDefaultDataPath
			, @DefaultLog AS InstanceDefaultLogPath
			, SERVERPROPERTY('InstanceName') AS InstanceName
			, SERVERPROPERTY('IsClustered') AS IsClustered
			, SERVERPROPERTY('IsFullTextInstalled') AS IsFullTextInstalled
			, SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled
			, SERVERPROPERTY('IsIntegratedSecurityOnly') AS IsIntegratedSecurityOnly
			, SERVERPROPERTY('IsLocalDB') AS IsLocalDB
			, SERVERPROPERTY('IsSingleUser') AS IsSingleUser
			, SERVERPROPERTY('IsXTPSupported') AS IsXTPSupported
			, SERVERPROPERTY('LCID') AS LCID
			, SERVERPROPERTY('LicenseType') AS LicenseType
			, SERVERPROPERTY('MachineName') AS MachineName
			, SERVERPROPERTY('NumLicenses') AS NumLicenses
			, SERVERPROPERTY('ProcessID') AS ProcessID
			, SERVERPROPERTY('ProductLevel') AS ProductLevel
			, SERVERPROPERTY('ProductVersion') AS ProductVersion
			, SERVERPROPERTY('ResourceLastUpdateDateTime') AS ResourceLastUpdateDateTime
			, SERVERPROPERTY('ResourceVersion') AS ResourceVersion
			, SERVERPROPERTY('ServerName') AS ServerName
			, SERVERPROPERTY('SqlCharSet') AS SqlCharSet
			, SERVERPROPERTY('SqlCharSetName') AS SqlCharSetName
			, SERVERPROPERTY('SqlSortOrder') AS SqlSortOrder
			, SERVERPROPERTY('SqlSortOrderName') AS SqlSortOrderName
			, GETDATE() AS [DataCollectionTime]
END





GO
GRANT EXECUTE ON  [dbo].[DBA_auditGetServerProperties] TO [dbaMonitoringUser]
GO
