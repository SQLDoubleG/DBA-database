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
-- Create date: 01/05/2014
-- Description:	Gets disks info for the current Machine
--
-- Parameters:	
--				@insertAuditTables, will insert the table [DBA].[dbo].[ServerDisksInformation_Loading]
--
-- Assumptions:	
--				xp_cmdshell is enabled in the server
--				19/03/2015 RAG - TRUSTWORTHY must be ON for [DBA] database and [sa] the owner as on remote servers, it will execute as 'dbo'
--								DO NOT ADD MEMBERS TO THE [db_owner] database role as that can compromise the security of the server
--
-- References:
--				http://www.mssqltips.com/sqlservertip/3037/getting-more-details-with-an-enhanced-xpfixeddrives-for-sql-server/
--				http://msdn.microsoft.com/en-us/library/windows/desktop/aa394173(v=vs.85).aspx
--
-- Change Log:	
--				03/06/2014 RAG	Included functionality in case xp_cmdshell is not enabled
--				19/03/2015 RAG	Added WITH EXECUTE AS 'dbo' due to lack of permissions on remote servers
--				26/06/2015 RAG	Added Custer size using fsutil, correct size should be 65,536 (64k) for volumes used for SQL Server Data and Log files.
--							https://msdn.microsoft.com/en-us/library/dd758814.aspx?f=255&MSPPError=-2147217396
--				29/08/2018 RAG	Changes:
--									- Changed logicalDisk for Volume in the wmi query to get the cluster size from there
--									- Also volume will bring mount points.
--								 
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditGetServerDisksInformation]
WITH EXECUTE AS 'dbo'
AS
BEGIN

	SET NOCOUNT ON

	IF OBJECT_ID('tempdb..#DrvLetter')	IS NOT NULL DROP TABLE #DrvLetter
	IF OBJECT_ID('tempdb..#DrvInfo')	IS NOT NULL	DROP TABLE #DrvInfo

	CREATE TABLE #DrvLetter (
		Drive VARCHAR(500) NULL)
	
	CREATE TABLE #fsutil (
		Property VARCHAR(500) NULL)

	CREATE TABLE #DrvInfo (
		ID				TINYINT IDENTITY(1,1)
		, Drive			NVARCHAR(256)
		, [FileSystem]	NVARCHAR(16)
		, [FreeMB]		INT
		, [SizeMB]		INT
		, [VolName]		SYSNAME NULL
		, [ClusterSize]	INT NULL
	)

	-- Columns are returned in alphabetical order with fixed length so we'll calculate where those columns start based on the column titles
	DECLARE @blockSizeIx	INT
	DECLARE @captionChIx	INT
	DECLARE @fileSystemChIx INT
	DECLARE @FreeSpaceChIx	INT
	DECLARE @CapacityIx		INT
	DECLARE @labelIx INT

	IF NOT EXISTS ( SELECT value 
						FROM sys.configurations AS c 
						WHERE c.configuration_id = 16390 -- xp_cmdshell
							AND c.value = 1 ) BEGIN

		RAISERROR( 'xp_cmdshell is not enabled in this server, information displayed only for drives that contain databases', 16, 0 )

		INSERT INTO #DrvInfo (Drive, FileSystem, FreeMB, SizeMB, VolName)
			SELECT DISTINCT LEFT(vs.volume_mount_point, 2) AS Drive
					, vs.file_system_type AS FileSystem
					, vs.available_bytes / 1024 / 1024 AS FreeMB
					, vs.total_bytes / 1024 / 1024 AS SizeMB
					, vs.logical_volume_name AS VolName
				FROM master.sys.master_files AS mf
					CROSS APPLY master.sys.dm_os_volume_stats (database_id, file_id) AS vs
	END 
	ELSE BEGIN 

		INSERT INTO #DrvLetter		
			EXEC xp_cmdshell 'wmic volume where drivetype="3" get blockSize, Capacity, Caption, FileSystem, FreeSpace, Label'

		SELECT @blockSizeIx			= CHARINDEX('BlockSize',	Drive) 
				, @CapacityIx		= CHARINDEX('Capacity',		Drive) 
				, @captionChIx		= CHARINDEX('Caption',		Drive) 
				, @fileSystemChIx	= CHARINDEX('FileSystem',	Drive) 
				, @FreeSpaceChIx	= CHARINDEX('FreeSpace',	Drive) 
				, @labelIx			= CHARINDEX('Label',		Drive) 
			FROM #DrvLetter
			WHERE Drive LIKE '%Caption%'

		-- Delete useless rows
		DELETE #DrvLetter
			WHERE ISNULL(Drive, '') = '' 
				OR LEN(Drive) < 4 
				OR Drive LIKE '%Caption%'
				OR Drive LIKE  '%\\%\Volume%'

		INSERT INTO #DrvInfo (ClusterSize, SizeMB, Drive, FileSystem, FreeMB,  VolName)
			SELECT [blockSize]		= CAST(SUBSTRING(Drive, @blockSizeIx, @CapacityIx - @blockSizeIx) AS BIGINT) 
					, SizeMB		= CAST(SUBSTRING(Drive, @CapacityIx, @captionChIx - @CapacityIx) AS BIGINT) / 1024 / 1024
					, Drive			= SUBSTRING(Drive,@captionChIx, @fileSystemChIx - @captionChIx)
					, FileSystem	= SUBSTRING(Drive, @fileSystemChIx, @FreeSpaceChIx - @fileSystemChIx)
					, FreeMB		= CAST(SUBSTRING(Drive, @FreeSpaceChIx, @labelIx - @FreeSpaceChIx) AS BIGINT) / 1024 / 1024
					, VolName		= SUBSTRING(Drive, @labelIx, LEN(Drive) - @labelIx)
				FROM #DrvLetter 
	END 
		
	SELECT CONVERT(SYSNAME, SERVERPROPERTY('MachineName')) AS MachineName
			, Drive
			, VolName
			, FileSystem
			, SizeMB
			, FreeMB
			, ClusterSize
			, GETDATE() AS [DataCollectionTime]
		FROM #DrvInfo 

	DROP TABLE #DrvLetter
	DROP TABLE #DrvInfo

	IF OBJECT_ID('tempdb..#DrvLetter')	IS NOT NULL DROP TABLE #DrvLetter

	IF OBJECT_ID('tempdb..#fsutil')		IS NOT NULL	DROP TABLE #fsutil

	IF OBJECT_ID('tempdb..#DrvInfo')	IS NOT NULL	DROP TABLE #DrvInfo


END




GO
GRANT EXECUTE ON  [dbo].[DBA_auditGetServerDisksInformation] TO [dbaMonitoringUser]
GO
