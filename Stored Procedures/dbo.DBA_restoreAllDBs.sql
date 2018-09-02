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
-- Create date: 27/08/2013
-- Description:	Returns restore statements for all databases in the current instance
--
-- Change Log:	23/01/2013	RAG - Added @dbFilesPath parameter to manually specify where to restore the databases
--				21/07/2016	RAG - Changed call to [dbo].[DBA_restoreDBfromBackup] to add new parameters
--				17/10/2017	RAG - Added parameter @dbLogsPath
--								- Added database name to the path
-- =============================================
CREATE PROCEDURE [dbo].[DBA_restoreAllDBs]	
	@InstanceName	SYSNAME			= NULL
	, @dbFilesPath	NVARCHAR(512)	= NULL
	, @dbLogsPath	NVARCHAR(512)	= NULL
AS
BEGIN
	
	SET NOCOUNT ON

	SET @InstanceName = ISNULL (@InstanceName, @@SERVERNAME)

	DECLARE	@debugging				BIT	= 1 -- Only to print statements, it's too risky execute this not knowing what is going to actually do
			--, @onlySystemDB			BIT	= 0 
			, @WithReplace			BIT	= 1
			, @RestoreLastBackup	BIT = 1

	DECLARE @db TABLE(ID INT IDENTITY, dbName SYSNAME)

	DECLARE @dbname					SYSNAME
			, @numDB				INT
			, @countDB				INT = 1
			, @startTime			DATETIME = GETDATE()
			, @startDBCC			DATETIME
			, @dbSpecificFilesPath	NVARCHAR(512)	= NULL
			, @dbSpecificLogsPath	NVARCHAR(512)	= NULL

	INSERT @db (dbName)
		--SELECT TOP 100 PERCENT [name] 
		--	FROM sys.databases 
		--	WHERE [name] NOT IN ('model', 'tempdb') 
		--		AND ( ISNULL(@onlySystemDB, 0) = 0 OR [name] IN ('master', 'msdb') )
		--		AND state = 0 
		SELECT TOP 100 PERCENT name
			FROM DBA.dbo.DatabaseInformation AS D
			WHERE D.server_name = @InstanceName
				AND D.name NOT IN ('model', 'tempdb') 
				AND D.state_desc = 'ONLINE'
			ORDER BY D.name

	SET @numDB = @@ROWCOUNT

	WHILE @countDB <= @numDB BEGIN 
		
		SELECT @dbname = dbName 
				, @dbSpecificFilesPath = CASE WHEN RIGHT(@dbFilesPath, 1) = N'\' THEN @dbFilesPath + dbName ELSE @dbFilesPath + N'\' + dbName END
				, @dbSpecificLogsPath = CASE WHEN RIGHT(@dbFilesPath, 1) = N'\' THEN @dbLogsPath + dbName ELSE @dbLogsPath + N'\' + dbName END
		FROM @db WHERE ID = @countDB

			EXECUTE [dbo].[DBA_restoreDBfromBackup] 
				@SourceInstanceName	= @InstanceName
				,@SourceDBName		= @dbname
				,@TargetDBName		= NULL
				,@SourceFileName	= NULL
				,@RestoreLastBackup = @RestoreLastBackup
				,@SourceFilePath	= NULL
				,@NewDataFilePath	= @dbSpecificFilesPath
				,@NewLogFilePath	= @dbSpecificLogsPath
				,@WithStopAt		= NULL
				,@WithReplace		= @WithReplace
				,@WithRecovery		= 1
				,@WithStats			= 0
				,@KeepDbOwner		= 1
				,@debugging			= @debugging
		
		PRINT CHAR(10) + 'Execution Time: ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startDBCC, GETDATE()) )

		SET @countDB = @countDB + 1		
	END

	PRINT CHAR(10) + '/****************************'
	PRINT 'Total Time        : ' + DBA.dbo.formatSecondsToHR( DATEDIFF (SECOND, @startTime, GETDATE()) )
	PRINT '*****************************/'

END

GO
