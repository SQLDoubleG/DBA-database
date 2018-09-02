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
-- Description:	Gets database info for the current instance
--
-- Parameters:	
--				@insertAuditTables, will insert the table [DBA].[dbo].[DatabaseInformation_Loading]
--
-- Assumptions:	
--				19/03/2015 RAG - TRUSTWORTHY must be ON for [DBA] database and [sa] the owner as on remote servers, it will execute as 'dbo'
--								DO NOT ADD MEMBERS TO THE [db_owner] database role as that can compromise the security of the server
--
-- Change Log:	
--				09/02/2015 RAG - Added last successful CHECKDB http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-when-did-dbcc-checkdb-last-run-successfully/
--				09/03/2015 RAG - Added version specific features
--				19/03/2015 RAG - Added WITH EXECUTE AS 'dbo' due to lack of permissions on remote servers
--				14/05/2015 RAG - Added [Num_VLF]
--				22/06/2015 RAG - Added DATA_PURITY flags. 
--									Check http://www.mssqltips.com/sqlservertip/1988/ensure-sql-server-data-purity-checks-are-performed/
--									Check http://www.sqlskills.com/blogs/paul/checkdb-from-every-angle-how-to-tell-if-data-purity-checks-will-be-run/
--				23/11/2015 RAG - Use TRY...CATCH as AG database replicas are online but maybe not accessible (readable). In that case the process does not stop
--				26/04/2016 RAG - Fixed wrong column names for backups, differential was pointing to file_filegroup
--				16/06/2015 RAG - Added column [log_reuse_wait_desc] which comes from [dbo].[DBA_databaseFilesInfo]
--				11/07/2016 SZO - Removed no longer needed comments.
--				18/07/2016 SZO - Added SQL Server 2016 columns
--				20/06/2018 RAG - Added SQL Server 2016-2017 column [is_temporal_history_retention_enabled]
--									Fixed typo in [is_mixed_page_allocation_on]
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditGetDatabaseInformation]
WITH EXECUTE AS 'dbo'
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @sql				NVARCHAR(MAX) 
	DECLARE @insert				NVARCHAR(MAX) 
	DECLARE @select				NVARCHAR(MAX) 
	DECLARE @column_list		NVARCHAR(MAX) 
	DECLARE @insert_column_list	NVARCHAR(MAX) 
	DECLARE @select_column_list	NVARCHAR(MAX) 

	IF OBJECT_ID('tempdb..#output')					IS NOT NULL DROP TABLE #output

	IF OBJECT_ID('tempdb..#database_files')			IS NOT NULL DROP TABLE #database_files

	IF OBJECT_ID('tempdb..#space_used')				IS NOT NULL DROP TABLE #space_used

	IF OBJECT_ID('tempdb..#bkps')					IS NOT NULL DROP TABLE #bkps

	IF OBJECT_ID('tempdb..#checkdb')				IS NOT NULL DROP TABLE #checkdb

	IF OBJECT_ID('tempdb..#dataPurity')				IS NOT NULL DROP TABLE #dataPurity

	IF OBJECT_ID('tempdb..#PAGE')					IS NOT NULL DROP TABLE #PAGE

	IF OBJECT_ID('tempdb..#output')					IS NOT NULL DROP TABLE #output

	IF OBJECT_ID('tempdb..#features')				IS NOT NULL DROP TABLE #features

	IF OBJECT_ID('tempdb..#Num_VLF')				IS NOT NULL DROP TABLE #Num_VLF

	IF OBJECT_ID('tempdb..#LogInfoTill2008_OneDB')	IS NOT NULL DROP TABLE #LogInfoTill2008_OneDB

	IF OBJECT_ID('tempdb..#LogInfo2012_OneDB')		IS NOT NULL DROP TABLE #LogInfo2012_OneDB

	-- Create a table with all possible colums to use it as output
	CREATE TABLE #output(
		[server_name] [sysname] NOT NULL,
		[name] [sysname] NOT NULL,
		[database_id] [int] NULL,
		[source_database_id] [int] NULL,
		[owner_sid] [varbinary](85) NULL,
		[create_date] [datetime] NULL,
		[compatibility_level] [tinyint] NULL,
		[collation_name] [sysname] NULL,
		[user_access] [tinyint] NULL,
		[user_access_desc] [nvarchar](60) NULL,
		[is_read_only] [bit] NULL,
		[is_auto_close_on] [bit] NULL,
		[is_auto_shrink_on] [bit] NULL,
		[state] [tinyint] NULL,
		[state_desc] [nvarchar](60) NULL,
		[is_in_standby] [bit] NULL,
		[is_cleanly_shutdown] [bit] NULL,
		[is_supplemental_logging_enabled] [bit] NULL,
		[snapshot_isolation_state] [tinyint] NULL,
		[snapshot_isolation_state_desc] [nvarchar](60) NULL,
		[is_read_committed_snapshot_on] [bit] NULL,
		[recovery_model] [tinyint] NULL,
		[recovery_model_desc] [nvarchar](60) NULL,
		[page_verify_option] [tinyint] NULL,
		[page_verify_option_desc] [nvarchar](60) NULL,
		[is_auto_create_stats_on] [bit] NULL,
		[is_auto_update_stats_on] [bit] NULL,
		[is_auto_update_stats_async_on] [bit] NULL,
		[is_ansi_null_default_on] [bit] NULL,
		[is_ansi_nulls_on] [bit] NULL,
		[is_ansi_padding_on] [bit] NULL,
		[is_ansi_warnings_on] [bit] NULL,
		[is_arithabort_on] [bit] NULL,
		[is_concat_null_yields_null_on] [bit] NULL,
		[is_numeric_roundabort_on] [bit] NULL,
		[is_quoted_identifier_on] [bit] NULL,
		[is_recursive_triggers_on] [bit] NULL,
		[is_cursor_close_on_commit_on] [bit] NULL,
		[is_local_cursor_default] [bit] NULL,
		[is_fulltext_enabled] [bit] NULL,
		[is_trustworthy_on] [bit] NULL,
		[is_db_chaining_on] [bit] NULL,
		[is_parameterization_forced] [bit] NULL,
		[is_master_key_encrypted_by_server] [bit] NULL,
		[is_published] [bit] NULL,
		[is_subscribed] [bit] NULL,
		[is_merge_published] [bit] NULL,
		[is_distributor] [bit] NULL,
		[is_sync_with_backup] [bit] NULL,
		[service_broker_guid] [uniqueidentifier] NULL,
		[is_broker_enabled] [bit] NULL,
		[log_reuse_wait] [tinyint] NULL,
		[log_reuse_wait_desc] [nvarchar](60) NULL,
		[is_date_correlation_on] [bit] NULL,
		[is_cdc_enabled] [bit] NULL,
		[is_encrypted] [bit] NULL,
		[is_honor_broker_priority_on] [bit] NULL,
		[replica_id] [uniqueidentifier] NULL,
		[group_database_id] [uniqueidentifier] NULL,
		[default_language_lcid] [smallint] NULL,
		[default_language_name] [nvarchar](128) NULL,
		[default_fulltext_language_lcid] [int] NULL,
		[default_fulltext_language_name] [nvarchar](128) NULL,
		[is_nested_triggers_on] [bit] NULL,
		[is_transform_noise_words_on] [bit] NULL,
		[two_digit_year_cutoff] [smallint] NULL,
		[containment] [tinyint] NULL,
		[containment_desc] [nvarchar](60) NULL,
		[target_recovery_time_in_seconds] [int] NULL,
		[is_memory_optimized_elevate_to_snapshot_on] [bit] NULL,
		[is_auto_create_stats_incremental_on] [bit] NULL,
		[is_query_store_on] [bit] NULL,
		[resource_pool_id] [int] NULL,
		[delayed_durability] [int] NULL,
		[delayed_durability_desc] [nvarchar](60) NULL,
		[is_federation_member] [bit] NULL,
		[is_remote_data_archive_enabled] [bit] NULL,
		[is_mixed_page_allocation_on] [bit] NULL,
		[is_temporal_retention_enabled] [bit] NULL,
		[is_temporal_history_retention_enabled] [BIT] NULL,
		[PrimaryFilePath] [nvarchar](255) NULL,
		[Size_MB] [decimal](10, 2) NULL,
		[SpaceAvailable_MB] [decimal](10, 2) NULL,
		[DataSpace_MB] [decimal](10, 2) NULL,
		[IndexSpace_MB] [decimal](10, 2) NULL,
		[LogSpace_MB] [decimal](10, 2) NULL,
		[LastBackupDate] [datetime] NULL,
		[LastLogBackupDate] [datetime] NULL,
		[LastDifferentialDatabaseBackupDate] [datetime] NULL,
		[LastFileFilegroupBackupDate] [datetime] NULL,
		[LastDifferentialFileBackupDate] [datetime] NULL,
		[LastPartialBackupDate] [datetime] NULL,
		[LastDifferentialPartialBackupDate] [datetime] NULL,
		[LastSuccessfulCheckDB] [datetime] NULL,
		[VersionSpecificFeatures] [nvarchar](255) NULL,
		[Num_VLF] [int] NULL,
		[DataPurityFlag] [tinyint] NULL,
		[DataCollectionTime] [datetime] NULL
	) 

	CREATE TABLE #database_files (
		database_id				INT
		, database_name			SYSNAME
		, [file_id]				INT	
		, logical_name			SYSNAME
		, type_desc				SYSNAME
		, [FileGroup]			SYSNAME			NULL
		, [is_FG_readonly]		VARCHAR(3)		NULL
		, size_mb				DECIMAL(10,2)
		, used_mb				DECIMAL(10,2)	NULL
		, AutoGrowth			VARCHAR(100)
		, percentage_used		DECIMAL(5,2)	NULL
		, log_reuse_wait_desc	NVARCHAR(60) 
		, [Path]				NVARCHAR(4000)
		, [FileName]			SYSNAME
		, DriveSizeGB			DECIMAL(10,2)
		, DriveFreeGB			DECIMAL(10,2)
		, DriveFreePercent		INT
		, ShrinkFile			VARCHAR(1000)
	)

	BEGIN TRY
		INSERT INTO #database_files
			EXECUTE DBA.dbo.[DBA_databaseFilesInfo]
	END TRY
	BEGIN CATCH
	END CATCH

	CREATE TABLE #space_used (
		database_name			SYSNAME
		, database_size_KB		BIGINT
		, unallocated_space_KB	BIGINT
		, reserved_KB			BIGINT
		, data_KB				BIGINT
		, index_KB				BIGINT
		, log_KB				BIGINT
		, used_KB				BIGINT
		, unused_KB				BIGINT
	)

	BEGIN TRY
		INSERT INTO #space_used
			EXECUTE [DBA].[dbo].[DBA_spaceused]
	END TRY
	BEGIN CATCH
	END CATCH

	CREATE TABLE #bkps(
		database_name								SYSNAME
		, last_full_backup_date						DATETIME NULL
		, last_log_backup_date						DATETIME NULL
		, last_differential_database_backup_date	DATETIME NULL
		, last_file_filegroup_backup_date			DATETIME NULL
		, last_differential_file_backup_date 		DATETIME NULL
		, last_partial_backup_date  				DATETIME NULL
		, last_differential_partial_backup_date 	DATETIME NULL
	)

	INSERT INTO #bkps
		SELECT database_name
				, [D] AS last_database_backup_date
				, [L] AS last_log_backup_date
				, [I] AS last_differential_database_backup_date
				, [F] AS last_file_filegroup_backup_date
				, [G] AS last_differential_file_backup_date 
				, [P] AS last_partial_backup_date  
				, [Q] AS last_differential_partial_backup_date 
			FROM (SELECT database_name, [type], backup_finish_date
					FROM msdb.dbo.backupset
					WHERE server_name = @@SERVERNAME) AS s
			PIVOT( 
				MAX(backup_finish_date)
				FOR [type] IN ([D], [L], [I], [F], [G], [P], [Q])) AS p


	CREATE TABLE #PAGE(
		ParentObject	VARCHAR(255) ,
		Object			VARCHAR(255) ,
		Field			VARCHAR(255) ,
		Value			VARCHAR(255) ,
		database_name	SYSNAME NULL
	)

	CREATE TABLE #features(
		database_id		INT
		, feature_name	SYSNAME
	)

	CREATE TABLE #Num_VLF (
			database_id			INT
			, Num_VLF			INT )

	CREATE TABLE #LogInfoTill2008_OneDB (
			FileId				INT 
			, FileSize			BIGINT
			, StartOffset		BIGINT
			, FSeqNo			INT
			, Status			INT
			, Parity			INT
			, CreateLSN			FLOAT)

	CREATE TABLE #LogInfo2012_OneDB (
			RecoveryUnitId		INT
			, FileId			INT 
			, FileSize			BIGINT
			, StartOffset		BIGINT
			, FSeqNo			INT
			, Status			INT
			, Parity			INT
			, CreateLSN			FLOAT)


	EXEC sp_MSforeachdb N'
		USE [?];

		INSERT #PAGE (ParentObject, Object, Field, Value)
			EXEC (''DBCC PAGE ([?], 1, 9, 3) WITH TABLERESULTS, NO_INFOMSGS'');
		
		UPDATE #PAGE SET database_name = N''?'' WHERE database_name IS NULL;

		INSERT INTO #features
			SELECT DB_ID() AS database_id, feature_name FROM sys.dm_db_persisted_sku_features;
		
		-- Calculate number of VLF
		TRUNCATE TABLE #LogInfoTill2008_OneDB
		TRUNCATE TABLE #LogInfo2012_OneDB

		IF DBA.dbo.getNumericSQLVersion(NULL) < 11 BEGIN
			INSERT INTO #LogInfoTill2008_OneDB
				EXECUTE sp_executesql N''DBCC LOGINFO WITH NO_INFOMSGS''

			INSERT INTO #Num_VLF
				SELECT DB_ID(), COUNT(*) FROM #LogInfoTill2008_OneDB
		END 
		ELSE BEGIN 
			INSERT INTO #LogInfo2012_OneDB
				EXECUTE sp_executesql N''DBCC LOGINFO WITH NO_INFOMSGS''

			INSERT INTO #Num_VLF
				SELECT DB_ID(), COUNT(*) FROM #LogInfo2012_OneDB

		END
	';
	-- Sometimes we have 2 values per database
	SELECT DISTINCT * INTO #checkdb		FROM #PAGE WHERE Field = 'dbi_dbccLastKnownGood'
	-- Get databases data purity flag
	SELECT DISTINCT * INTO #dataPurity	FROM #PAGE WHERE Field = 'dbi_DBCCFlags'


	-- Get all columns from sys.databases, there are more columns in newer versions of SQL Server, hence we calculate them dynamically
	SET @column_list = 	(SELECT ', ' + QUOTENAME(name) AS [text()] 
							FROM sys.all_columns WHERE object_id = OBJECT_ID('sys.databases')
							ORDER BY column_id 
							FOR XML PATH(''))

	SET @insert_column_list = N'[server_name]' + @column_list + N', [PrimaryFilePath], [Size_MB], [SpaceAvailable_MB], [DataSpace_MB], [IndexSpace_MB], [LogSpace_MB]' + 
							N', [LastBackupDate], [LastLogBackupDate], [LastDifferentialDatabaseBackupDate] ,[LastFileFilegroupBackupDate] ,[LastDifferentialFileBackupDate]' + 
							N', [LastPartialBackupDate] ,[LastDifferentialPartialBackupDate], [LastSuccessfulCheckDB], [VersionSpecificFeatures], [Num_VLF], [DataPurityFlag], [DataCollectionTime]'
	
	SET @select_column_list = N'@@SERVERNAME AS [server_name]' + REPLACE(@column_list, N'[', N'd.[') -- to avoid column name conflict 

	SET @insert = N'INSERT INTO #output (' + @insert_column_list + N')' + CHAR(10)
	SET @select = N'
		SELECT ' + @select_column_list + CHAR(10) + CONVERT(NVARCHAR(MAX), N'
				, primaryDBFile.[Path]												AS [PrimaryFilePath]
				, CONVERT(DECIMAL(10,2), space_used.database_size_KB / 1024.)		AS [Size_MB]
				, CONVERT(DECIMAL(10,2), space_used.unallocated_space_KB / 1024.)	AS [SpaceAvailable_MB]
				, CONVERT(DECIMAL(10,2), space_used.data_KB / 1024.)				AS [DataSpace_MB]
				, CONVERT(DECIMAL(10,2), space_used.index_KB / 1024.)				AS [IndexSpace_MB]
				, CONVERT(DECIMAL(10,2), space_used.log_KB / 1024.)					AS [LogSpace_MB]
				, bkp.last_full_backup_date											AS [LastBackupDate]
				, bkp.last_log_backup_date											AS [LastLogBackupDate]
				, last_differential_database_backup_date							AS [LastDifferentialDatabaseBackupDate]
				, last_file_filegroup_backup_date									AS [LastFileFilegroupBackupDate]			
				, last_differential_file_backup_date 								AS [LastDifferentialFileBackupDate]
				, last_partial_backup_date  										AS [LastPartialBackupDate]
				, last_differential_partial_backup_date								AS [LastDifferentialPartialBackupDate]
				, CONVERT(DATETIME, checkdb.Value)									AS [LastSuccessfulCheckDB]
				, STUFF((SELECT '', '' + feature_name 
							FROM #features
							WHERE database_id = d.database_id
							FOR XML PATH('''')), 1, 2, '''')						AS [VersionSpecificFeatures]
				, [Num_VLF]
				, [dataPurity].[Value] AS [DataPurityFlag]
				, GETDATE()															AS [DataCollectionTime]
			FROM sys.databases AS d
				LEFT JOIN #bkps AS bkp
					ON bkp.database_name = d.name
				LEFT JOIN #database_files AS primaryDBFile
					ON primaryDBFile.database_id = d.database_id
						AND primaryDBFile.file_id = 1
				LEFT JOIN #space_used AS space_used
					ON space_used.database_name = d.name
				LEFT JOIN #checkdb AS checkdb
					ON checkdb.database_name = d.name
				LEFT JOIN #dataPurity AS dataPurity
					ON dataPurity.database_name = d.name
				LEFT JOIN #Num_VLF AS vlf
					ON vlf.database_id = d.database_id')

	--PRINT @insert
	--PRINT @select
	
	SET @sql	= @insert + @select 

	EXECUTE sp_executesql @sql

	SELECT [server_name]
			,[name]
			,[database_id]
			,[source_database_id]
			,DB_NAME([source_database_id]) AS [source_database_name]
			,[owner_sid]
			,SUSER_SNAME([owner_sid]) AS [owner_name]
			,[create_date]
			,[compatibility_level]
			,[collation_name]
			,[user_access]
			,[user_access_desc]
			,[is_read_only]
			,[is_auto_close_on]
			,[is_auto_shrink_on]
			,[state]
			,[state_desc]
			,[is_in_standby]
			,[is_cleanly_shutdown]
			,[is_supplemental_logging_enabled]
			,[snapshot_isolation_state]
			,[snapshot_isolation_state_desc]
			,[is_read_committed_snapshot_on]
			,[recovery_model]
			,[recovery_model_desc]
			,[page_verify_option]
			,[page_verify_option_desc]
			,[is_auto_create_stats_on]
			,[is_auto_update_stats_on]
			,[is_auto_update_stats_async_on]
			,[is_ansi_null_default_on]
			,[is_ansi_nulls_on]
			,[is_ansi_padding_on]
			,[is_ansi_warnings_on]
			,[is_arithabort_on]
			,[is_concat_null_yields_null_on]
			,[is_numeric_roundabort_on]
			,[is_quoted_identifier_on]
			,[is_recursive_triggers_on]
			,[is_cursor_close_on_commit_on]
			,[is_local_cursor_default]
			,[is_fulltext_enabled]
			,[is_trustworthy_on]
			,[is_db_chaining_on]
			,[is_parameterization_forced]
			,[is_master_key_encrypted_by_server]
			,[is_published]
			,[is_subscribed]
			,[is_merge_published]
			,[is_distributor]
			,[is_sync_with_backup]
			,[service_broker_guid]
			,[is_broker_enabled]
			,[log_reuse_wait]
			,[log_reuse_wait_desc]
			,[is_date_correlation_on]
			,[is_cdc_enabled]
			,[is_encrypted]
			,[is_honor_broker_priority_on]
			,[replica_id]
			,[group_database_id]
			,[default_language_lcid]
			,[default_language_name]
			,[default_fulltext_language_lcid]
			,[default_fulltext_language_name]
			,[is_nested_triggers_on]
			,[is_transform_noise_words_on]
			,[two_digit_year_cutoff]
			,[containment]
			,[containment_desc]
			,[target_recovery_time_in_seconds]
			,[is_memory_optimized_elevate_to_snapshot_on]
			,[is_auto_create_stats_incremental_on]
			,[is_query_store_on]
			,[resource_pool_id]
			,[delayed_durability]
			,[delayed_durability_desc]
			,[PrimaryFilePath]
			,[Size_MB]
			,[SpaceAvailable_MB]
			,[DataSpace_MB]
			,[IndexSpace_MB]
			,[LogSpace_MB]
			,[LastBackupDate]
			,[LastLogBackupDate]
			,[LastDifferentialDatabaseBackupDate]
			,[LastFileFilegroupBackupDate]
			,[LastDifferentialFileBackupDate]
			,[LastPartialBackupDate]
			,[LastDifferentialPartialBackupDate]
			,[LastSuccessfulCheckDB]
			,[VersionSpecificFeatures]
			,[Num_VLF]
			,[DataPurityFlag]
			,[DataCollectionTime]
			,[is_federation_member]
			,[is_remote_data_archive_enabled]
			,[is_mixed_page_allocation_on]
			,[is_temporal_retention_enabled]
			,[is_temporal_history_retention_enabled]
		FROM #output

	IF OBJECT_ID('tempdb..#output')					IS NOT NULL DROP TABLE #output

	IF OBJECT_ID('tempdb..#database_files')			IS NOT NULL DROP TABLE #database_files

	IF OBJECT_ID('tempdb..#space_used')				IS NOT NULL DROP TABLE #space_used

	IF OBJECT_ID('tempdb..#bkps')					IS NOT NULL DROP TABLE #bkps

	IF OBJECT_ID('tempdb..#checkdb')				IS NOT NULL DROP TABLE #checkdb

	IF OBJECT_ID('tempdb..#dataPurity')				IS NOT NULL DROP TABLE #dataPurity

	IF OBJECT_ID('tempdb..#PAGE')					IS NOT NULL DROP TABLE #PAGE

	IF OBJECT_ID('tempdb..#output')					IS NOT NULL DROP TABLE #output

	IF OBJECT_ID('tempdb..#features')				IS NOT NULL DROP TABLE #features

	IF OBJECT_ID('tempdb..#Num_VLF')				IS NOT NULL DROP TABLE #Num_VLF

	IF OBJECT_ID('tempdb..#LogInfoTill2008_OneDB')	IS NOT NULL DROP TABLE #LogInfoTill2008_OneDB

	IF OBJECT_ID('tempdb..#LogInfo2012_OneDB')		IS NOT NULL DROP TABLE #LogInfo2012_OneDB


END
GO
GRANT EXECUTE ON  [dbo].[DBA_auditGetDatabaseInformation] TO [dbaMonitoringUser]
GO
