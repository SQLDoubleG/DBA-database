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
-- Create date: 20/05/2015
-- Description:	Retuns a list of servers along with login and password to connect
--
-- Parameters:
--				@onePerMachine	= Will return only one row per machine in case of multiple instances
--				@isAdmin		= Will return [sysadmin] login and password for each machine
--
-- Log History:	
--				10/02/2016	RAG - Added ISNULL(p.IsIntegratedSecurityOnly, 0) because new servers do not have info yet
--			
-- =============================================
CREATE PROCEDURE [dbo].[DBA_getServersToMonitor]
	@onePerMachine	BIT = 0
	, @isAdmin		BIT = 0
	, @server_name  SYSNAME = NULL
AS
BEGIN

	SET NOCOUNT ON

	SET @onePerMachine	= ISNULL(@onePerMachine, 0)
	SET @isAdmin		= ISNULL(@isAdmin, 0)

	OPEN SYMMETRIC KEY PasswordColumns
	   DECRYPTION BY CERTIFICATE DBA_Certificate;

	
	SELECT ISNULL(server_ip_address, s.server_name) AS ServerName
			, CASE WHEN ISNULL(p.IsIntegratedSecurityOnly, 0) = 0 THEN 
				CASE WHEN @isAdmin = 1 THEN adminLogin ELSE monitoringLogin END 
				ELSE NULL 
			END AS remoteLogin
			,CASE WHEN ISNULL(p.IsIntegratedSecurityOnly, 0) = 0 THEN  
				CASE 
					WHEN @isAdmin = 1 THEN CONVERT(nvarchar, DecryptByKey(adminPassword, 1 , HashBytes('SHA1', CONVERT(varbinary, s.ID)))) 
					ELSE CONVERT(NVARCHAR, DECRYPTBYKEY(monitoringPassword, 1 , HASHBYTES('SHA1', CONVERT(varbinary, s.ID))))
					END 
				ELSE NULL 
			END AS remotePassword
		INTO #r
		FROM dbo.ServerList AS s
		LEFT JOIN dbo.ServerProperties AS p
			ON p.server_name = s.server_name
		WHERE isSQLServer = 1
			AND MonitoringActive = 1
			AND s.server_name = ISNULL(@server_name, s.server_name)

	CLOSE SYMMETRIC KEY PasswordColumns

	
	IF @onePerMachine = 0 BEGIN
		SELECT * FROM #r
		ORDER BY 1
	END 
	ELSE BEGIN
		SELECT MIN(ServerName) AS ServerName
				, CASE WHEN CHARINDEX('\', ServerName) <> 0 THEN LEFT(ServerName, CHARINDEX('\', ServerName) - 1) ELSE ServerName END AS MachineName
				, remoteLogin
				, remotePassword
			FROM #r
			GROUP BY remoteLogin
				, remotePassword
				, CASE WHEN CHARINDEX('\', ServerName) <> 0 THEN LEFT(ServerName, CHARINDEX('\', ServerName) - 1) ELSE ServerName END 
			ORDER BY 1
	END
	
END
GO
