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
-- Create date: 23/06/2016 
-- Description:	Persists index usage information in [dbo].[IndexUsageStatsHistory] 
--					This sp will run daily and on demand during index maintenance due to some SQL versions 
--					resetting this information on index rebuilds 
--				The process will look at sys.dm_db_index_usage_stats and compare to the previous execution 
--					- If the current values are smaller than last time we collected the data, means they have been reset 
--						usage stats, so we can add those values to the totals 
--					- If the current values are bigger than last time we collected the data, means they have not been reset 
--						usage stats, so we need to take the difference before adding it to the totals 
-- 
-- Parameters: 
--				@dbname		-> Optional, all user databases if NULL  
--				@object_id	-> Optional, all objects if not specified 
--				@index_id	-> Optional, all indexes if not specified. Only accepts value distinct than NULL if @object_is is NOT NULL 
-- 
-- Log History:	22/06/2016	RAG	- Created 
--				11/08/2016	RAG	- Added check for online replicas and (NOLOCK) for system views 
--				14/09/2016	RAG	- Removed validation for PRIMARY replicas. 
--									Databases are now coming from [dbo].[DBA_getDatabasesMaintenanceList] where all validations are done but dbname 
--				16/03/2017	RAG	- Added [index_name] to the MERGE statement because it can happen you drop an index and creating a new one
--									will get the same index_id as the previous.
--				14/07/2017	SZO - BUG FIX: added ISNULL() around index_name to account for heaps with no index_name getting multiple inserts 
--				04/01/2018	RAG	- Added columns from [dbo].[DBA_getDatabasesMaintenanceList]
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
--								- Added clause not to run on secondary databases if they are not readable
-- 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_indexUsageStatsPersistsHistory] 
	@dbname			SYSNAME = NULL 
	, @object_id	INT = NULL 
	, @index_id		INT = NULL 
	, @debugging	BIT = 0 
AS 
BEGIN 
 
SET NOCOUNT ON 
 
DECLARE @sql								NVARCHAR(MAX) 
		, @role								TINYINT
		, @secondary_role_allow_connections TINYINT
 
SET @debugging = ISNULL(@debugging, 0) 
 
IF @object_id IS NULL AND @index_id IS NOT NULL BEGIN 
	RAISERROR (N'You cannot specify @index_id without specifying @object_id', 16, 1, 1) 
	RETURN -100 
END 
 
DECLARE @db TABLE(database_id INT NOT NULL PRIMARY KEY, database_name SYSNAME NOT NULL, role TINYINT NOT NULL, secondary_role_allow_connections TINYINT NOT NULL)
 
INSERT INTO @db (database_id, database_name, role, secondary_role_allow_connections)
	EXECUTE [dbo].[DBA_getDatabasesMaintenanceList] 
 
DECLARE dbs CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
	SELECT db.database_name, db.role, db.secondary_role_allow_connections
		FROM @db AS db 
			WHERE db.database_name LIKE ISNULL(@dbname, db.database_name) 
 
OPEN dbs 
FETCH NEXT FROM dbs INTO @dbname, @role, @secondary_role_allow_connections
 
WHILE @@FETCH_STATUS = 0 BEGIN 

	IF @role = 2 AND @secondary_role_allow_connections = 0 BEGIN -- Secondary
		FETCH NEXT FROM dbs INTO @dbname, @role, @secondary_role_allow_connections
		CONTINUE
	END

PRINT N'Processing database : ' + QUOTENAME(@dbname) 
 
	SET @sql = N'USE ' + QUOTENAME(@dbname) + CONVERT(NVARCHAR(MAX), N' 
 
;WITH s AS ( 
SELECT @@SERVERNAME AS server_name 
			, DB_ID() AS [database_id] 
			, DB_NAME() AS [database_name] 
			, OBJECT_SCHEMA_NAME(ix.object_id) AS [schema_name] 
			, ix.object_id 
			, OBJECT_NAME(ix.object_id) AS [object_name] 
			, ix.index_id 
			, ix.name AS [index_name] 
			, ISNULL(ius.[user_seeks]	, 0) AS [user_seeks]	 
			, ISNULL(ius.[user_scans]	, 0) AS [user_scans]	 
			, ISNULL(ius.[user_lookups]	, 0) AS [user_lookups] 
			, ISNULL(ius.[user_updates]	, 0) AS [user_updates] 
			, ius.[last_user_seek] 
			, ius.[last_user_scan] 
			, ius.[last_user_lookup] 
			, ius.[last_user_update] 
			, ISNULL(ius.[system_seeks]	 , 0) AS [system_seeks] 
			, ISNULL(ius.[system_scans]	 , 0) AS [system_scans] 
			, ISNULL(ius.[system_lookups], 0) AS [system_lookups] 
			, ISNULL(ius.[system_updates], 0) AS [system_updates] 
			, ius.[last_system_seek] 
			, ius.[last_system_scan] 
			, ius.[last_system_lookup] 
			, ius.[last_system_update] 
 
		FROM sys.indexes AS ix WITH(NOLOCK) 
			LEFT JOIN sys.dm_db_index_usage_stats AS ius WITH(NOLOCK) 
				ON ius.object_id = ix.object_id 
					AND ius.index_id = ix.index_id 
					AND ius.database_id = DB_ID() 
		WHERE ix.object_id	= ISNULL(@object_id, ix.object_id) 
			AND ix.index_id	= ISNULL(@index_id, ix.index_id) 
			AND OBJECTPROPERTYEX(ix.object_id, ''IsMsShipped'') = 0 
) 
 
MERGE DBA.[dbo].[IndexUsageStatsHistory] AS t 
	USING s 
		ON s.server_name				= t.server_name 
		AND s.database_name				= t.database_name  
		AND s.object_id					= t.object_id  
		AND s.index_id					= t.index_id  
		AND ISNULL(s.index_name, '''')	= ISNULL(t.index_name, '''')  COLLATE DATABASE_DEFAULT
	WHEN NOT MATCHED THEN  
		INSERT ([server_name],[database_id],[database_name],[schema_name],[object_id],[object_name],[index_id],[index_name] 
				,[total_user_seeks],[total_user_scans],[total_user_lookups],[total_user_updates] 
				,[user_seeks],[user_scans],[user_lookups],[user_updates] 
				,[last_user_seek],[last_user_scan],[last_user_lookup],[last_user_update] 
				,[total_system_seeks],[total_system_scans],[total_system_lookups],[total_system_updates] 
				,[system_seeks],[system_scans],[system_lookups],[system_updates] 
				,[last_system_seek],[last_system_scan],[last_system_lookup],[last_system_update],[created_date],[modified_date]) 
 
		VALUES ([server_name],[database_id],[database_name],[schema_name],[object_id],[object_name],[index_id],[index_name] 
				,[user_seeks],[user_scans],[user_lookups],[user_updates] -- Same for total_ and user_ 
				,[user_seeks],[user_scans],[user_lookups],[user_updates] -- Same for total_ and user_ 
				,[last_user_seek],[last_user_scan],[last_user_lookup],[last_user_update] 
				,[system_seeks],[system_scans],[system_lookups],[system_updates] -- Same for total_ and system_ 
				,[system_seeks],[system_scans],[system_lookups],[system_updates] -- Same for total_ and system_ 
				,[last_system_seek],[last_system_scan],[last_system_lookup],[last_system_update],GETDATE(),GETDATE()) 
 
	WHEN MATCHED THEN UPDATE SET 
		t.[total_user_seeks]		+= CASE WHEN t.[user_seeks]		> s.[user_seeks]	THEN s.[user_seeks]		ELSE s.[user_seeks]		- t.[user_seeks]	END --- cumulative			 
		, t.[total_user_scans]		+= CASE WHEN t.[user_scans]		> s.[user_scans]	THEN s.[user_scans]		ELSE s.[user_scans]		- t.[user_scans]	END -- cumulative 
		, t.[total_user_lookups]	+= CASE WHEN t.[user_lookups]	> s.[user_lookups]	THEN s.[user_lookups]	ELSE s.[user_lookups]	- t.[user_lookups]	END -- cumulative 
		, t.[total_user_updates]	+= CASE WHEN t.[user_updates] 	> s.[user_updates] 	THEN s.[user_updates] 	ELSE s.[user_updates] 	- t.[user_updates] 	END -- cumulative 
		, t.[user_seeks]			= s.[user_seeks] 
		, t.[user_scans]			= s.[user_scans] 
		, t.[user_lookups]			= s.[user_lookups] 
		, t.[user_updates]			= s.[user_updates] 
		, t.[last_user_seek]		= s.[last_user_seek]		 
		, t.[last_user_scan]		= s.[last_user_scan]		 
		, t.[last_user_lookup]		= s.[last_user_lookup]		 
		, t.[last_user_update]		= s.[last_user_update]		 
		, t.[total_system_seeks]	+= CASE WHEN t.[system_seeks]	> s.[system_seeks]		THEN s.[system_seeks]	ELSE s.[system_seeks]	- t.[system_seeks]		END-- cumulative		 
		, t.[total_system_scans]	+= CASE WHEN t.[system_scans]	> s.[system_scans]		THEN s.[system_scans]	ELSE s.[system_scans]	- t.[system_scans]		END-- cumulative 
		, t.[total_system_lookups]	+= CASE WHEN t.[system_lookups]	> s.[system_lookups]	THEN s.[system_lookups]	ELSE s.[system_lookups]	- t.[system_lookups]	END-- cumulative 
		, t.[total_system_updates]	+= CASE WHEN t.[system_updates]	> s.[system_updates]	THEN s.[system_updates]	ELSE s.[system_updates]	- t.[system_updates]	END-- cumulative 
		, t.[system_seeks]			= s.[system_seeks] 
		, t.[system_scans]			= s.[system_scans] 
		, t.[system_lookups]		= s.[system_lookups] 
		, t.[system_updates]		= s.[system_updates] 
		, t.[last_system_seek]		= s.[last_system_seek]		 
		, t.[last_system_scan]		= s.[last_system_scan]		 
		, t.[last_system_lookup]	= s.[last_system_lookup]	 
		, t.[last_system_update]	= s.[last_system_update] 
		, t.[modified_date]			= GETDATE() 
	; 
') 
	 
	IF @debugging = 0 
		EXECUTE sp_executesql 
			@stmt = @sql
			, @params = N'@object_id INT, @index_id INT'
			, @object_id = @object_id
			, @index_id = @index_id 
	ELSE 
		PRINT @sql 
 
	FETCH NEXT FROM dbs INTO @dbname, @role, @secondary_role_allow_connections
 
END 
 
CLOSE dbs 
DEALLOCATE dbs 
 
END 
 
GO
