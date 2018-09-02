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
-- Create date: 21/05/2013
-- Description:	Return a list of databases for a given instance
--				with useful information
--
-- Change Log:
--				25/04/2016	RAG	Changed column backupSchedule as it's not bitwise anymore
--
-- =============================================
CREATE PROCEDURE [dbo].[repInstanceDatabases] 
	@instanceName	SYSNAME = NULL
	, @databaseName	SYSNAME = NULL

AS
BEGIN
	
	SET NOCOUNT ON

	SELECT  CASE WHEN database_id <= 4 THEN 1 ELSE 0 END AS isSystemDatabase
			, I.server_name AS [InstanceName]
			, D.name AS [DatabaseName]
			, D.database_id AS [DatabaseId]
			, D.owner_name AS [Owner]
			, D.compatibility_level AS [CompatibilityLevel]
			, D.collation_name AS [Collation]
			, D.user_access_desc AS [UserAccess]
			,	CASE 
					WHEN D.[state_desc] = 'Deleted' AND S.isAccessible = 0 THEN 'Not Accessible'
					ELSE [state_desc]
				END AS [Status]
			, D.recovery_model AS [RecoveryModel]
			, D.page_verify_option_desc AS [PageVerify]
			, D.is_auto_create_stats_on AS [AutoCreateStatisticsEnabled]
			, D.is_auto_update_stats_on AS [AutoUpdateStatisticsEnabled]
			, D.is_auto_update_stats_async_on AS [AutoUpdateStatisticsAsync]
			, D.is_trustworthy_on AS [Trustworthy]
			, D.is_db_chaining_on AS [DatabaseOwnershipChaining]
			, D.SpaceAvailable_MB AS [SpaceAvailable]
			, D.is_broker_enabled AS [BrokerEnabled]
			, [PrimaryFilePath]
			, D.DataSpace_MB AS [DataSpaceUsage]
			, D.Size_MB AS [Size]
			, I.backupRootPath
			, [LastBackupDate]
			, [LastLogBackupDate]
			, CASE WHEN D.collation_name LIKE '%CS%' THEN 'Yes' ELSE 'No' END AS [CaseSensitive]
			, D.is_auto_shrink_on AS [AutoShrink]
			, D.is_auto_close_on AS [AutoClose]
			, D.DataCollectionTime AS [LastDataCollectionTime]
			, ''
			, BackupSchedule
			--, ISNULL( STUFF( (SELECT N', ' + name FROM DBA.dbo.DaysOfWeekBitWise AS B WHERE B.bitValue & [backupSchedule] = B.bitValue FOR XML PATH('') ), 1, 2, '' ), 'None' ) AS BackupSchedule
		FROM [DBA].[dbo].[DatabaseInformation] AS D
			INNER JOIN [DBA].[dbo].ServerConfigurations AS I
				ON I.server_name = D.server_name
			INNER JOIN [DBA].[dbo].ServerProperties AS P
				ON P.server_name = D.server_name
			INNER JOIN [DBA].[dbo].[ServerInformation] AS S
				ON S.server_name = P.MachineName
		WHERE I.server_name LIKE ISNULL(@instanceName, I.server_name)
			AND D.name LIKE ISNULL(@databaseName, D.name)
		ORDER BY S.server_name, I.server_name, isSystemDatabase DESC, D.name
END




GO
