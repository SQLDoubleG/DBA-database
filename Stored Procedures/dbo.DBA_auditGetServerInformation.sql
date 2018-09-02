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
-- Create date: 14/01/2014
-- Description:	Gets Server Information
--
-- Parameters:	
--				@insertAuditTables, will insert the table [DBA].[dbo].[ServerInformation_Loading]
--
-- Assumptions:	
--				19/03/2015 RAG - TRUSTWORTHY must be ON for [DBA] database and [sa] the owner as on remote servers, it will execute as 'dbo'
--								DO NOT ADD MEMBERS TO THE [db_owner] database role as that can compromise the security of the server
--
-- Change Log:	
--				05/06/2014 RAG - Added CPU columns
--				18/03/2015 RAG - removed all xp_instance_regread calls due to lack of permissions on remote servers, use ps instead
--				19/03/2015 RAG - Added WITH EXECUTE AS 'dbo' due to lack of permissions on remote servers
--				20/03/2015 RAG - Changed Get-CimInstance for Get-WmiObject to work in W2008
--				20/03/2015 RAG - Get Processor model, machine model with ps
--				06/04/2016 SZO - Added power_plan variable, xp_cmdshell/Powershell and data parsing for Power Scheme.
--				11/07/2016 SZO - Removed no longer necessary comments from script.
--				26/07/2016 RAG - Get Host name in case is as VM
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditGetServerInformation]
WITH EXECUTE AS 'dbo'
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @HostName				SYSNAME
	DECLARE @server_name			SYSNAME		= CONVERT(SYSNAME, SERVERPROPERTY('MachineName'))
    DECLARE @processor_name			NVARCHAR(255)
    DECLARE @manufacturer			NVARCHAR(255)
    DECLARE @model					NVARCHAR(255)
    DECLARE @Caption				NVARCHAR(255)
	DECLARE @CSDVersion				NVARCHAR(255)
	DECLARE @Version				NVARCHAR(255)
	--DECLARE @build					SQL_VARIANT
	DECLARE @LastBootUpTime			DATETIME
	DECLARE @DataCollectionTime		DATETIME	= GETDATE()
	DECLARE @TotalMemorySize		INT
	DECLARE @TotalVisibleMemorySize INT
	DECLARE @TotalMemoryModules		INT
	DECLARE @OSArchitecture			NVARCHAR(255)
	DECLARE @IPAddress				NVARCHAR(255)

	DECLARE @cpu_count				INT
	DECLARE @cores_per_cpu			INT
	DECLARE @logical_cpu_count		INT

	DECLARE @psTable				TABLE(data NVARCHAR(512) NULL)

	DECLARE @PowerPlan				NVARCHAR(20);
	
	EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters',	N'PhysicalHostName', @HostName		OUTPUT    

	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter ''IPEnabled = True'' | select-object IPAddress | format-list * "'

	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "Get-WmiObject -Class Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors | format-list * "'
	
	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "Get-WmiObject -Class Win32_computersystem | Select-Object NumberOfProcessors, Manufacturer, Model | format-list *"' 

	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "Get-WmiObject -Class Win32_PhysicalMemory | Select-Object Capacity | format-list * "'
	
	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "''LastBootUpTime: '' + [Management.ManagementDateTimeConverter]::ToDateTime((Get-WmiObject Win32_OperatingSystem).LastBootUpTime)"'

	INSERT INTO @psTable
		EXECUTE xp_cmdshell 'powershell.exe "Get-WmiObject -Class Win32_OperatingSystem | Select-Object Caption, Version, CSDVersion, OSArchitecture, TotalVisibleMemorySize | format-list *"' 

	INSERT INTO @psTable
	    EXECUTE xp_cmdshell 'powershell.exe "Powercfg -getactivescheme | Format-List *"'
	
	DELETE @psTable WHERE data IS NULL
	
	SELECT @Caption					= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'Caption%'
	SELECT @Version					= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'Version%'
	SELECT @CSDVersion				= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'CSDVersion%'
	SELECT @LastBootUpTime			= CONVERT(DATETIME, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)), 101) FROM @psTable WHERE data LIKE 'LastBootUpTime%'
	SELECT @OSArchitecture			= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'OSArchitecture%'
	SELECT @TotalMemorySize			= CONVERT(INT, SUM(CONVERT(BIGINT, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data))) / 1048576)) FROM @psTable WHERE data LIKE 'Capacity%'
	SELECT @TotalMemoryModules		= COUNT(*) FROM @psTable WHERE data LIKE 'Capacity%'
	SELECT @TotalVisibleMemorySize	= CONVERT(INT, CEILING(SUM(CONVERT(BIGINT, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data))) / 1024.))) FROM @psTable WHERE data LIKE 'TotalVisibleMemorySize%'
	SELECT @cpu_count				= CONVERT(INT, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data))) FROM @psTable WHERE data LIKE 'NumberOfProcessors%'
	SELECT @cores_per_cpu			= CONVERT(INT, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data))) FROM @psTable WHERE data LIKE 'NumberOfCores%'
	SELECT @logical_cpu_count		= SUM(CONVERT(INT, SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)))) FROM @psTable WHERE data LIKE 'NumberOfLogicalProcessors%'
	SELECT @manufacturer			= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'Manufacturer%'
	SELECT @model					= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'Model%'
	SELECT @processor_name			= SUBSTRING(data, CHARINDEX(':', data) + 2, LEN(data)) FROM @psTable WHERE data LIKE 'Name%'
	SELECT @IPAddress				= STUFF( (SELECT ', ' + SUBSTRING(data, CHARINDEX('{', data), LEN(data)) FROM @psTable WHERE data LIKE 'IPAddress%' FOR XML PATH('') ), 1, 2, '')

	SELECT @PowerPlan				= SUBSTRING([data], CHARINDEX('(', [data]) + 1, (CHARINDEX(')', [data], CHARINDEX('(', [data])) - CHARINDEX('(', [data])) - 1) FROM @psTable WHERE [data] LIKE '%Power Scheme%';
	
	SELECT @server_name AS [server_name]
			, @Caption AS [OS]
			, @OSArchitecture AS [OSArchitecture]
			, @CSDVersion AS [OSPatchLevel]
			--, CONVERT(NVARCHAR(255), @Version) + '.' + CONVERT(VARCHAR, @build) AS [version]
			, @Version AS [OSVersion]
			, @LastBootUpTime AS [LastBootUpTime]
			, @TotalVisibleMemorySize AS [TotalVisibleMemorySize]
			, @TotalMemorySize AS [TotalPhysicalMemorySize]
			, @TotalMemoryModules AS [TotalMemoryModules]
			, @IPAddress AS [IPAddress]
			, @cpu_count AS physical_cpu_count
			, @cores_per_cpu AS cores_per_cpu
			, @logical_cpu_count AS logical_cpu_count
			, @manufacturer AS manufacturer
			, CASE 
					WHEN LOWER(@manufacturer) LIKE '%vmware%' THEN N'Virtual Machine'
					WHEN LOWER(@model) LIKE '%virtual%' THEN @model + N' on ' + @HostName 
					ELSE @model 
				END AS server_model
			, @processor_name AS processor_name
			, @DataCollectionTime AS [DataCollectionTime] 
			, @PowerPlan AS [power_plan];
	
END




GO
GRANT EXECUTE ON  [dbo].[DBA_auditGetServerInformation] TO [dbaMonitoringUser]
GO
