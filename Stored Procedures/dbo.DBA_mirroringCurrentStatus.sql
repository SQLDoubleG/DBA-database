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
-- Create date: 24/10/2013
-- Description:	Returns the current status of the mirroring sessions
-- 
-- Change Log:	
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_mirroringCurrentStatus]	
	@dbName	SYSNAME = NULL
AS 
BEGIN

	SET NOCOUNT ON
	SET QUOTED_IDENTIFIER ON -- Keep it!
	
	SELECT @@SERVERNAME AS InstanceName
			, DB_NAME(database_id) AS DatabaseName
			, mirroring_role_desc
			, mirroring_state_desc
			, mirroring_witness_name
			, mirroring_witness_state_desc
			, mirroring_safety_level_desc
		FROM sys.database_mirroring 
		WHERE mirroring_state IS NOT NULL
			AND DB_NAME(database_id) LIKE ISNULL(@dbName, DB_NAME(database_id))
		ORDER BY DatabaseName
END





GO
