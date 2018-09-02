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
-- Create date: 19/07/2013
-- Description:	Returns the Backup Path for a given Instance - Database, 
--				Database backup paths are defined either at database level in [DBA].dbo.DatabaseInformation column backupRootPath
--				or Instance level (+ Database Name) in [DBA].dbo.InstanceInformation column backupRootPath
-- 
-- Parameters:	- @InstanceName	-> Instance where the database is
--				- @DatabaseName	-> Database name
-- Examples:
--				SELECT [dbo].[getBackupRootPath](@@SERVERNAME, 'dbName')
--
-- Change Log:	
--				04/10/2013 - RAG The fuction will return the Server Default backup path + Database Name 
--								when that is not defined neither in DBA.dbo.DatabaseInformation nor DBA.dbo.InstanceInformation 
--				06/11/2013 - RAG Calculate each path separately if the precedent cannot be determined. 
--								This way helps if the database is not currently registered in DBA.dbo.DatabaseInformation
--
-- =============================================
CREATE FUNCTION [dbo].[getBackupRootPath](
	@InstanceName	SYSNAME
	, @DatabaseName	SYSNAME
)
RETURNS NVARCHAR(256)
AS
BEGIN

	DECLARE @BackupPath NVARCHAR(256)

	-- database level
	SET @BackupPath		= ( SELECT D.backupRootPath FROM DBA.dbo.DatabaseInformation AS D WHERE D.server_name = @InstanceName AND D.name = @DatabaseName )
	
	-- instance level
	IF @BackupPath IS NULL 
		SET @BackupPath	= ( SELECT I.backupRootPath + @DatabaseName + '\' FROM DBA.dbo.ServerConfigurations AS I WHERE I.server_name = @InstanceName )
	
	-- instance default
	IF @BackupPath IS NULL
		SET @BackupPath	= ( SELECT BackupDirectory + @DatabaseName + '\' FROM dbo.getInstanceDefaultPaths(@InstanceName) )

	RETURN @BackupPath

END



GO
