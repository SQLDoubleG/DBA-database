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
-- Create date: May 2013
-- Description:	Return a list of servers with useful information
-- =============================================
CREATE PROCEDURE [dbo].[repServers]
AS
BEGIN
	
	SET NOCOUNT ON

    SELECT S.server_name AS [ServerName]
			,[OS]
			,[OSArchitecture]
			,[OSPatchLevel]
			,[OSVersion]
			,[TotalVisibleMemorySize]
			,CONVERT(VARCHAR, [LastBootUpTime], 103) + ' ' + CONVERT(VARCHAR, [LastBootUpTime], 108) AS [LastBootUpTime]
			,[TotalVisibleMemorySize] AS [UsableRAM]
			,[TotalPhysicalMemorySize] AS [InstalledRAM]
			,CONVERT(VARCHAR, [DataCollectionTime], 103) + ' ' + CONVERT(VARCHAR, [DataCollectionTime], 108) AS [LastDataCollectionTime]
		FROM [DBA].[dbo].[ServerInformation] as S
		ORDER BY ServerName
END




GO
GRANT EXECUTE ON  [dbo].[repServers] TO [public]
GO
