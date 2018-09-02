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
-- Author:		RAG
-- Create date: 26/03/2013
-- Description:	Process the database information collected in [dbo].[DatabaseInformation_Loading]
--
-- Log:
--				26/03/2013	RAG - Added new column ReplicationOptions to the table
--				21/05/2013	RAG - Created as Stored Procedure
--				21/05/2013	RAG - Added case WHEN NOT MATCHED BY SOURCE to flag dropped databases as [status] = 'Deleted'
--				04/06/2013	RAG - Removed Insert into DabaseSizeInformation as it fails when database was not found and last data collected exist already there,
--									so a new MERGE statement will do the job
--				15/07/2013	RAG - System databases are included in the PS step and therefore included here
--				31/07/2013	RAG - As per http://msdn.microsoft.com/en-us/library/ms365937(v=sql.105).aspx, Resource and tempdb cannot be backup
--				13/11/2014	RAG - Included INSERT into _history tables
--				24/04/2015	RAG - Included check to delete rows only if there are any rows for that server, to avoid deleting if the server wasn't accessible
--				14/05/2015	RAG - Included [VersionSpecificFeatures] and [Num_VLF]
--				25/06/2015	RAG - Included [DataPurityFlag]
--				22/06/2016	RAG - Included [IndexMaintenanceSchedule],[DBCCSchedule],[UpdateStatsSchedule]
--				27/06/2016	SZO - Renamed [UpdateStatsSchedule] to [StatisticsMaintenanceSchedule]
--				12/03/2018	RAG	- Added email alert when something has changed
--				23/03/2018	RAG	- Insert a row in DatabaseSizeInfo at least once a month (1st of the month) even if size has not changed
--				20/06/2018	RAG - Added SQL Server 2016-2017 column [is_temporal_history_retention_enabled]
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessDatabaseInformation] 
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @SQLtableHTML	NVARCHAR(MAX);
	DECLARE @tableHTML		NVARCHAR(MAX) = '';
	DECLARE @HTML			NVARCHAR(MAX);
	DECLARE @emailSubject	NVARCHAR(128) = 'Database Settings Change';

	IF NOT EXISTS (SELECT * FROM dbo.DatabaseInformation_Loading) BEGIN
		RAISERROR ('The table [dbo].[DatabaseInformation_Loading] is empty, please run the loading process and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	-- Get all distinct servers we got information about, so we can delete databases not found as long as the server was reachable 
	SELECT DISTINCT server_name 
		INTO #server_reached
	FROM dbo.DatabaseInformation_Loading
	
	BEGIN TRY
		BEGIN TRAN

		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT [Action],[server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
				,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
				,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
				,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
				,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
				,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
				,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
				,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
				,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
				,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
				,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
				,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
				,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
				,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
				,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
				,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
				,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
				,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
				,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo],[KeepNBackups],[IndexMaintenanceSchedule],[DBCCSchedule]
				,[StatisticsMaintenanceSchedule],[DataCollectionTime],[RowCheckSum],[is_federation_member],[is_remote_data_archive_enabled]
				,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled]
			INTO #h
			FROM dbo.DatabaseInformation_History
			WHERE 1=0
		
		INSERT INTO #h
		SELECT [Action],[server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
				,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
				,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
				,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
				,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
				,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
				,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
				,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
				,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
				,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
				,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
				,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
				,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
				,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
				,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
				,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
				,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
				,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
				,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo],[KeepNBackups],[IndexMaintenanceSchedule],[DBCCSchedule]
				,[StatisticsMaintenanceSchedule],[DataCollectionTime],[RowCheckSum],[is_federation_member],[is_remote_data_archive_enabled]
				,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled]
			FROM (
			MERGE INTO dbo.DatabaseInformation t
				USING dbo.DatabaseInformation_Loading AS s
					ON s.server_name = t.server_name
						AND s.name = t.name
				WHEN NOT MATCHED THEN 
					INSERT ([server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
						,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
						,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
						,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
						,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
						,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
						,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
						,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
						,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
						,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
						,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
						,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
						,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
						,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
						,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
						,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
						,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
						,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
						--,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo]
						,[KeepNBackups]
						--,[IndexMaintenanceSchedule],[DBCCSchedule],[StatisticsMaintenanceSchedule]
						,[DataCollectionTime],/*[RowCheckSum],*/[is_federation_member],[is_remote_data_archive_enabled]
						,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled])
					VALUES ([server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
						,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
						,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
						,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
						,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
						,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
						,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
						,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
						,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
						,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
						,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
						,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
						,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
						,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
						,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
						,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
						,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
						,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
						--,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo]
						,(SELECT MAX(keepNBackups) FROM dbo.ServerConfigurations WHERE server_name = s.server_name)
						--,[IndexMaintenanceSchedule],[DBCCSchedule],[StatisticsMaintenanceSchedule]
						,[DataCollectionTime],/*[RowCheckSum],*/[is_federation_member],[is_remote_data_archive_enabled]
						,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled])
			
				WHEN MATCHED THEN 
					UPDATE
						SET t.[database_id]									= s.[database_id]
							,t.[source_database_id]							= s.[source_database_id]
							,t.[source_database_name]						= s.[source_database_name]
							,t.[owner_sid]									= s.[owner_sid]
							,t.[owner_name]									= s.[owner_name]
							,t.[create_date]								= s.[create_date]
							,t.[compatibility_level]						= s.[compatibility_level]
							,t.[collation_name]								= s.[collation_name]
							,t.[user_access]								= s.[user_access]
							,t.[user_access_desc]							= s.[user_access_desc]
							,t.[is_read_only]								= s.[is_read_only]
							,t.[is_auto_close_on]							= s.[is_auto_close_on]
							,t.[is_auto_shrink_on]							= s.[is_auto_shrink_on]
							,t.[state]										= s.[state]
							,t.[state_desc]									= s.[state_desc]
							,t.[is_in_standby]								= s.[is_in_standby]
							,t.[is_cleanly_shutdown]						= s.[is_cleanly_shutdown]
							,t.[is_supplemental_logging_enabled]			= s.[is_supplemental_logging_enabled]
							,t.[snapshot_isolation_state]					= s.[snapshot_isolation_state]
							,t.[snapshot_isolation_state_desc]				= s.[snapshot_isolation_state_desc]
							,t.[is_read_committed_snapshot_on]				= s.[is_read_committed_snapshot_on]
							,t.[recovery_model]								= s.[recovery_model]
							,t.[recovery_model_desc]						= s.[recovery_model_desc]
							,t.[page_verify_option]							= s.[page_verify_option]
							,t.[page_verify_option_desc]					= s.[page_verify_option_desc]
							,t.[is_auto_create_stats_on]					= s.[is_auto_create_stats_on]
							,t.[is_auto_update_stats_on]					= s.[is_auto_update_stats_on]
							,t.[is_auto_update_stats_async_on]				= s.[is_auto_update_stats_async_on]
							,t.[is_ansi_null_default_on]					= s.[is_ansi_null_default_on]
							,t.[is_ansi_nulls_on]							= s.[is_ansi_nulls_on]
							,t.[is_ansi_padding_on]							= s.[is_ansi_padding_on]
							,t.[is_ansi_warnings_on]						= s.[is_ansi_warnings_on]
							,t.[is_arithabort_on]							= s.[is_arithabort_on]
							,t.[is_concat_null_yields_null_on]				= s.[is_concat_null_yields_null_on]
							,t.[is_numeric_roundabort_on]					= s.[is_numeric_roundabort_on]
							,t.[is_quoted_identifier_on]					= s.[is_quoted_identifier_on]
							,t.[is_recursive_triggers_on]					= s.[is_recursive_triggers_on]
							,t.[is_cursor_close_on_commit_on]				= s.[is_cursor_close_on_commit_on]
							,t.[is_local_cursor_default]					= s.[is_local_cursor_default]
							,t.[is_fulltext_enabled]						= s.[is_fulltext_enabled]
							,t.[is_trustworthy_on]							= s.[is_trustworthy_on]
							,t.[is_db_chaining_on]							= s.[is_db_chaining_on]
							,t.[is_parameterization_forced]					= s.[is_parameterization_forced]
							,t.[is_master_key_encrypted_by_server]			= s.[is_master_key_encrypted_by_server]
							,t.[is_published]								= s.[is_published]
							,t.[is_subscribed]								= s.[is_subscribed]
							,t.[is_merge_published]							= s.[is_merge_published]
							,t.[is_distributor]								= s.[is_distributor]
							,t.[is_sync_with_backup]						= s.[is_sync_with_backup]
							,t.[service_broker_guid]						= s.[service_broker_guid]
							,t.[is_broker_enabled]							= s.[is_broker_enabled]
							,t.[log_reuse_wait]								= s.[log_reuse_wait]
							,t.[log_reuse_wait_desc]						= s.[log_reuse_wait_desc]
							,t.[is_date_correlation_on]						= s.[is_date_correlation_on]
							,t.[is_cdc_enabled]								= s.[is_cdc_enabled]
							,t.[is_encrypted]								= s.[is_encrypted]
							,t.[is_honor_broker_priority_on]				= s.[is_honor_broker_priority_on]
							,t.[replica_id]									= s.[replica_id]
							,t.[group_database_id]							= s.[group_database_id]
							,t.[default_language_lcid]						= s.[default_language_lcid]
							,t.[default_language_name]						= s.[default_language_name]
							,t.[default_fulltext_language_lcid]				= s.[default_fulltext_language_lcid]
							,t.[default_fulltext_language_name]				= s.[default_fulltext_language_name]
							,t.[is_nested_triggers_on]						= s.[is_nested_triggers_on]
							,t.[is_transform_noise_words_on]				= s.[is_transform_noise_words_on]
							,t.[two_digit_year_cutoff]						= s.[two_digit_year_cutoff]
							,t.[containment]								= s.[containment]
							,t.[containment_desc]							= s.[containment_desc]
							,t.[target_recovery_time_in_seconds]			= s.[target_recovery_time_in_seconds]
							,t.[is_memory_optimized_elevate_to_snapshot_on]	= s.[is_memory_optimized_elevate_to_snapshot_on]
							,t.[is_auto_create_stats_incremental_on]		= s.[is_auto_create_stats_incremental_on]
							,t.[is_query_store_on]							= s.[is_query_store_on]
							,t.[resource_pool_id]							= s.[resource_pool_id]
							,t.[delayed_durability]							= s.[delayed_durability]
							,t.[delayed_durability_desc]					= s.[delayed_durability_desc]
							,t.[PrimaryFilePath]							= s.[PrimaryFilePath]
							,t.[Size_MB]									= s.[Size_MB]
							,t.[SpaceAvailable_MB]							= s.[SpaceAvailable_MB]
							,t.[DataSpace_MB]								= s.[DataSpace_MB]
							,t.[IndexSpace_MB]								= s.[IndexSpace_MB]
							,t.[LogSpace_MB]								= s.[LogSpace_MB]
							,t.[LastBackupDate]								= s.[LastBackupDate]
							,t.[LastLogBackupDate]							= s.[LastLogBackupDate]
							,t.[LastDifferentialDatabaseBackupDate]			= s.[LastDifferentialDatabaseBackupDate]
							,t.[LastFileFilegroupBackupDate]				= s.[LastFileFilegroupBackupDate]
							,t.[LastDifferentialFileBackupDate]				= s.[LastDifferentialFileBackupDate]
							,t.[LastPartialBackupDate]						= s.[LastPartialBackupDate]
							,t.[LastDifferentialPartialBackupDate]			= s.[LastDifferentialPartialBackupDate]
							,t.[LastSuccessfulCheckDB]						= s.[LastSuccessfulCheckDB]
							,t.[VersionSpecificFeatures]					= s.[VersionSpecificFeatures]
							,t.[Num_VLF]									= s.[Num_VLF]
							,t.[DataPurityFlag]								= s.[DataPurityFlag]
							-- THESE ARE CUSTOM COLUMNS, SO THEY WON'T COME IN THE _Loading TABLE
							--,t.[BackupSchedule]							= s.[BackupSchedule]
							--,t.[BackupRootPath]							= s.[BackupRootPath]
							--,t.[BackupNFiles]								= s.[BackupNFiles]
							--,t.[BackupBatchNo]							= s.[BackupBatchNo]
							--,t.[KeepNBackups]								= s.[KeepNBackups]
							--,t.[IndexMaintenanceSchedule]					= s.[IndexMaintenanceSchedule]
							--,t.[DBCCSchedule]								= s.[DBCCSchedule]
							--,t.[StatisticsMaintenanceSchedule]			= s.[StatisticsMaintenanceSchedule]
							,t.[DataCollectionTime]							= s.[DataCollectionTime]
							,t.[is_federation_member]						= s.[is_federation_member]
							,t.[is_remote_data_archive_enabled]				= s.[is_remote_data_archive_enabled]
							,t.[is_mixed_page_allocation_on]				= s.[is_mixed_page_allocation_on]
							,t.[is_temporal_retention_enabled]				= s.[is_temporal_retention_enabled]
							,t.[is_temporal_history_retention_enabled]		= s.[is_temporal_history_retention_enabled]
  
				WHEN NOT MATCHED BY SOURCE 
					-- Either we don't care about that server any more or we reach the server but wans't there (deleted)
					AND (t.server_name NOT IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor])  
						OR t.server_name IN (SELECT server_name FROM #server_reached)) THEN 
					DELETE
			OUTPUT $action AS [Action], deleted.*) AS History 
		WHERE [Action] IN ('UPDATE', 'DELETE');

		-- Check what we have UPDATED/DELETED and if it differs of what exists in _history, we insert it
		MERGE dbo.DatabaseInformation_History AS t
			USING #h AS s
				ON s.server_name = t.server_name
					AND s.name = t.name
					AND s.[RowCheckSum] = t.[RowCheckSum]
			WHEN NOT MATCHED THEN 
				INSERT ([Action],[server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
					,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
					,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
					,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
					,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
					,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
					,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
					,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
					,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
					,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
					,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
					,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
					,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
					,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
					,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
					,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
					,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
					,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
					,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo],[KeepNBackups],[IndexMaintenanceSchedule],[DBCCSchedule]
					,[StatisticsMaintenanceSchedule],[DataCollectionTime],[RowCheckSum],[is_federation_member],[is_remote_data_archive_enabled]
					,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled])
				VALUES ([Action],[server_name],[name],[database_id],[source_database_id],[source_database_name],[owner_sid],[owner_name],[create_date]
					,[compatibility_level],[collation_name],[user_access],[user_access_desc],[is_read_only],[is_auto_close_on],[is_auto_shrink_on]
					,[state],[state_desc],[is_in_standby],[is_cleanly_shutdown],[is_supplemental_logging_enabled],[snapshot_isolation_state]
					,[snapshot_isolation_state_desc],[is_read_committed_snapshot_on],[recovery_model],[recovery_model_desc],[page_verify_option]
					,[page_verify_option_desc],[is_auto_create_stats_on],[is_auto_update_stats_on],[is_auto_update_stats_async_on]
					,[is_ansi_null_default_on],[is_ansi_nulls_on],[is_ansi_padding_on],[is_ansi_warnings_on],[is_arithabort_on]
					,[is_concat_null_yields_null_on],[is_numeric_roundabort_on],[is_quoted_identifier_on],[is_recursive_triggers_on]
					,[is_cursor_close_on_commit_on],[is_local_cursor_default],[is_fulltext_enabled],[is_trustworthy_on],[is_db_chaining_on]
					,[is_parameterization_forced],[is_master_key_encrypted_by_server],[is_published],[is_subscribed],[is_merge_published]
					,[is_distributor],[is_sync_with_backup],[service_broker_guid],[is_broker_enabled],[log_reuse_wait],[log_reuse_wait_desc]
					,[is_date_correlation_on],[is_cdc_enabled],[is_encrypted],[is_honor_broker_priority_on],[replica_id],[group_database_id]
					,[default_language_lcid],[default_language_name],[default_fulltext_language_lcid],[default_fulltext_language_name]
					,[is_nested_triggers_on],[is_transform_noise_words_on],[two_digit_year_cutoff],[containment],[containment_desc]
					,[target_recovery_time_in_seconds],[is_memory_optimized_elevate_to_snapshot_on],[is_auto_create_stats_incremental_on]
					,[is_query_store_on],[resource_pool_id],[delayed_durability],[delayed_durability_desc],[PrimaryFilePath],[Size_MB]
					,[SpaceAvailable_MB],[DataSpace_MB],[IndexSpace_MB],[LogSpace_MB],[LastBackupDate],[LastLogBackupDate]
					,[LastDifferentialDatabaseBackupDate],[LastFileFilegroupBackupDate],[LastDifferentialFileBackupDate],[LastPartialBackupDate]
					,[LastDifferentialPartialBackupDate],[LastSuccessfulCheckDB],[VersionSpecificFeatures],[Num_VLF],[DataPurityFlag]
					,[BackupSchedule],[BackupRootPath],[BackupNFiles],[BackupBatchNo],[KeepNBackups],[IndexMaintenanceSchedule],[DBCCSchedule]
					,[StatisticsMaintenanceSchedule],[DataCollectionTime],[RowCheckSum],[is_federation_member],[is_remote_data_archive_enabled]
					,[is_mixed_page_allocation_on],[is_temporal_retention_enabled],[is_temporal_history_retention_enabled]);	

		MERGE dbo.DatabaseSizeInformation AS t
			USING (SELECT server_name, name, [DataCollectionTime], [Size_MB], [SpaceAvailable_MB], [DataSpace_MB], [IndexSpace_MB], [LogSpace_MB]
							, CHECKSUM(server_name, name, [Size_MB], [SpaceAvailable_MB], [DataSpace_MB], [IndexSpace_MB], [LogSpace_MB]) AS [RowCheckSum]
					FROM dbo.DatabaseInformation_Loading ) AS s
				ON s.server_name = t.server_name 
					AND s.name = t.name 
					AND s.[RowCheckSum] = t.[RowCheckSum]
					AND DATEPART(DAY, s.DataCollectionTime) <> 1
			
			WHEN NOT MATCHED THEN 
				INSERT (server_name, name, [DataCollectionTime], [Size_MB], [SpaceAvailable_MB], [DataSpace_MB], [IndexSpace_MB], [LogSpace_MB], [RowCheckSum])
					VALUES (server_name, name, [DataCollectionTime], [Size_MB], [SpaceAvailable_MB], [DataSpace_MB], [IndexSpace_MB], [LogSpace_MB], [RowCheckSum]);
		
		UPDATE dbo.DatabaseInformation
			SET BackupSchedule = '-------'
			WHERE name IN ('resource', 'tempdb') -- Be sure no backups are taken

		TRUNCATE TABLE dbo.DatabaseInformation_Loading;

		COMMIT;

		-- This query will return the differences between the new and old records.
		SET @SQLtableHTML = 'SET @tableHTML = (SELECT CONVERT(VARCHAR(MAX), ''<tr><td class="h">[server_name]-[database_name]</td><td class="h">'' + ISNULL(CONVERT(VARCHAR(256), del.server_name), '''') + ''</td><td class="h">''';
		SET @SQLtableHTML += '+ ISNULL(CONVERT(VARCHAR(256), del.name), '''') + ''</td></tr>''';

		SET @SQLtableHTML += ( SELECT ' + CASE WHEN ISNULL(CONVERT(VARCHAR(256),ins.'+ QUOTENAME(name) +'),'''') <> ISNULL(CONVERT(VARCHAR(256),del.'+ QUOTENAME(name) +'),'''') THEN ''<tr><td>' 
										+  name 
										+ '</td><td class="d">'' + ISNULL(CONVERT(VARCHAR(256), del.' 
										+ QUOTENAME(name) + '), '''') + ''</td><td class="i">'' + ISNULL(CONVERT(VARCHAR(256), ins.'
										+ QUOTENAME(name) + '), '''') + ''</td></tr>'' ELSE '''' END' + CHAR(10)
									FROM sys.columns
									WHERE object_id = OBJECT_ID('dbo.DatabaseInformation')
										AND name NOT IN ('ID', 'server_name', 'name', 'RowCheckSum')
									ORDER BY column_id 
									FOR XML PATH(''))
						
		SET @SQLtableHTML += ')
					FROM #h	AS del	
						INNER JOIN dbo.DatabaseInformation AS ins
							ON ins.server_name = del.server_name
								AND ins.name = del.name
					WHERE del.RowCheckSum <> ins.RowCheckSum
					ORDER BY ins.server_name, ins.name
					FOR XML PATH(''''));
					';

		-- After generating the string using FOR XML, these simbols get replaced by their HTML entities, so we need them back
		SET @SQLtableHTML = REPLACE(REPLACE(@SQLtableHTML, '&lt;', '<'), '&gt;', '>');

		EXECUTE sp_executesql @stmt = @SQLtableHTML, @params = N'@tableHTML NVARCHAR(MAX) OUTPUT', @tableHTML = @tableHTML OUTPUT

		-- The query above also generates symbols that were replaced by their HTML entities, so we need them back
		SET @tableHTML = REPLACE(REPLACE(@tableHTML, '&lt;', '<'), '&gt;', '>');

		SET @HTML = N'<html><head><style type="text/css">.ac{text-align:center}.diff {color:red} th{background-color:#5B9BD5;color:white;font-weight:bold;width:250px} td {white-space:nowrap;} .i{color:green;} .d{color:red;} .h{background-color:lightblue;font-weight:bold;}</style></head><body>'
						+ N'<table border="1">'
						+ N'<tr class="ac">'
						+ N'<th>Configuration Name</th>' 						
						+ N'<th>Previous Value</th>'
						+ N'<th>Current Value</th></tr>'
						+ @tableHTML
						+ '</table>'
						+ '</body></html>';

		--SELECT @HTML

		IF EXISTS (SELECT 1 
						FROM #h	AS del	
							INNER JOIN dbo.DatabaseInformation AS ins
								ON ins.server_name = del.server_name
									AND ins.name = del.name
						WHERE del.RowCheckSum <> ins.RowCheckSum) BEGIN

			EXEC msdb.dbo.sp_send_dbmail @profile_name = 'Admin Profile'
			  , @recipients = 'DatabaseAdministrators@rws.com'
			  , @subject = @emailSubject
			  , @body = @HTML
			  , @body_format = 'HTML';
		END;

	END TRY
	BEGIN CATCH
		SELECT ERROR_MESSAGE();
		ROLLBACK
	END CATCH
END
GO
