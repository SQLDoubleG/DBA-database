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
-- Description:	Return a list of hard drives for a given server
--				with useful information
-- =============================================
CREATE PROCEDURE [dbo].[repServerDisks]
	@serverName	SYSNAME = NULL
AS
BEGIN
	
	SET NOCOUNT ON

    SELECT	D.server_name AS ServerName
			, Drive
			, VolName
			, FileSystem
			, SizeMB
			, SizeMB / 1024 AS sizeGB
			, FreeMB
			, FreeMB / 1024 AS FreeGB
			, FreePercent
			, Message
			, S.DataCollectionTime AS LastDataCollectionTime
		FROM dbo.ServerDisksInformation AS D
			INNER JOIN dbo.ServerInformation AS S
				ON S.server_name = D.server_name
		WHERE D.server_name = ISNULL(@serverName, D.server_name)
		ORDER BY D.server_name
			, Drive
END




GO
GRANT EXECUTE ON  [dbo].[repServerDisks] TO [public]
GO
