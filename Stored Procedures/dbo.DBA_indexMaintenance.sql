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
-- Create date: 28/03/2013 
-- Description:	Rebuild / Reorganise Indexes (if required) 
-- Log: 
--				06/03/2013	RAG	- Added @timestamp variable to show time taken for each step. 
--				20/03/2013	RAG	- Added the rowcount as threshold to REBUILD indexes (disabled for now) 
--									 Removed the CURSOR based queries and replaced with WHILE loops									 
--				28/03/2013	RAG	- Added functionality to backup the tranlog by calling new stored procedure master.dbo.DBA_runLogBackup 
--									 Moved the sp_updatestats to a new job which runs on Sun 3am 
--				09/04/2013	RAG	- Added functionality to handle tables with LOB data, which cannot be rebuilt ONLINE 
--				15/05/2013	RAG	- Created as SP in DBA database which will be replicated accross all the servers  
--									and therefore accessible. 
--				15/08/2013	RAG	- Added functionallity to handle indexed views created with ANSI_NULLS OFF (Agresso styla) and REORGANIZE instead of REBUILD 
--				10/09/2013	RAG	- Added functionallity to handle when the index has allow_page _locks OFF (Documentum styla) to REBUILD as REORGANIZE is not possible 
--									this can be changed and ALTER the INDEX to allow page locks and then REORGANIZE, but since maintenance is done on weekends, rebuild 
--									and take the index offline is not an issue. (for not Enterprise versions) 
--				15/09/2013	RAG	- Add filter to not process read_only databases 
--				31/10/2013	RAG	- Add filter to not process objects created by an internal SQL Server component 
--				05/11/2013	RAG	- Removed join with DBA.dbo.DatabaseInformation when a database name is specified 
--				25/04/2014	RAG	- Added functionality to rebuild fulltext catalogs 
--				11/06/2014	RAG	- Added functionality to verify that MAXDOP does not exceed the total of physical cores 
--				22/06/2016	RAG	- Recreated as DBA_IndexMaintenance (previously DBA_reorganiseRebuildIndexes) 
--									- Added functionality to persist index usage information by calling a new sp [DBA].[dbo].[DBA_indexUsageStatsPersistsHistory] 
--									- Added parameters to modify the thresholds for reorganizing/rebuilding along with the min index size (in pages) 
--									- Mofified the scheduling system to store that in a new column in DBA.dbo.DatabaseInformation called [IndexMaintenanceSchedule] 
--										which will hold weekly schedule in a CHAR(7) format 
--				04/07/2016	RAG	- Added parameter @weekDayOverride which gives functionality to override the day of the week we want to run the process for. 
--				06/07/2016	RAG	- Changed the value of [DataCollectionTime] to be the same for all rows as looks like GETDATE() can change from one row to another 
--				18/07/2016	RAG	- Added validation for PRIMARY replicas in case there are AG configured as it failed for Servers pre 2012 
--				14/09/2016	RAG	- Removed validation for PRIMARY replicas. 
--									Databases are now coming from [dbo].[DBA_getDatabasesMaintenanceList] where all validations are done but dbname 
--				21/02/2017	RAG	- Bug fix: scheduleand batchNo were ignored with tha last change
--				21/02/2017	RAG	- Temporarily disable the FT rebuild as it takes too long and runs too frequent.
--				04/01/2018	RAG	- Added columns from [dbo].[DBA_getDatabasesMaintenanceList]
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
--								- Added clause not to run on secondary databases
--				16/01/2018	SZO	- Added ability to log time spent on finding fragmentation.
--				23/01/2018	SZO	- Bug fix: Removed unwanted square brackets being pulled in from the FIND_FRAG action.
--				07/03/2018	RAG	- Added @partition_number to take it into account for inserting 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_indexMaintenance] 
	@dbname					SYSNAME = NULL 
	, @minFragReorganize	FLOAT	= 10.0	-- min Fragmentation to consider reorganizing an index 
	, @minFragRebuild		FLOAT	= 30.0	-- min Fragmentation to consider rebuilding an index 
	, @minPageCount			BIGINT	= 1000 
	, @maxdop				TINYINT = 0 
	, @batchNo				TINYINT = NULL 
	, @weekDayOverride		TINYINT = NULL 
	, @debugging			BIT		= 0 -- SET TO 0 FOR THE SP TO DO ITS JOB, OTHERWISE WILL JUST PRINT OUT THE STATEMENTS!!!! 
AS 
BEGIN  

	SET NOCOUNT ON 

	-- Adjust parameters 
	SET @minFragReorganize	= ISNULL(@minFragReorganize, 10.0) 
	SET @minFragRebuild		= ISNULL(@minFragRebuild, 30.0) 
	SET @minPageCount		= ISNULL(@minPageCount, 1000) 
	SET @maxdop				= ISNULL(@maxdop, 0) 
	SET @batchNo			= CASE WHEN @dbname IS NULL THEN @batchNo ELSE NULL END -- when @dbname is provided it does not matter the batchNo 
	SET @debugging			= ISNULL(@debugging, 0) 

	DECLARE @db TABLE(database_id INT NOT NULL PRIMARY KEY, name SYSNAME NOT NULL, role TINYINT NOT NULL, secondary_role_allow_connections TINYINT NOT NULL)

	IF ISNULL(@weekDayOverride, DATEPART(WEEKDAY, GETDATE())) NOT BETWEEN 1 AND 7  BEGIN  
		RAISERROR ('The value specified for @weekDayOverride is not valid, please specify a value between 1 and 7', 16, 0) 
		RETURN -50 
	END  

	DECLARE	@sqlString		NVARCHAR(MAX) 
			, @dayOfTheWeek INT = ISNULL(@weekDayOverride, DATEPART(WEEKDAY, GETDATE())) 

	DECLARE @time			DATETIME 

	DECLARE @numCores		INT = ( SELECT ( cpu_count / hyperthread_ratio ) -- number of CPU's * number of physical cores per CPU 
											*  
											CASE WHEN hyperthread_ratio = cpu_count THEN cpu_count 
												ELSE ( ( cpu_count - hyperthread_ratio ) / ( cpu_count / hyperthread_ratio ) ) 
											END 
										FROM sys.dm_os_sys_info ) 

	-- MAXDOP to be <= than the number of physical cores 
	IF @maxdop > @numCores BEGIN  
		RAISERROR ('The MAXDOP specified exceeds the number of physical cores in the server, MAXDOP will be set to 0', 0, 0) 
		SET @maxdop		= 0  
	END  

	INSERT INTO @db (database_id, name, role, secondary_role_allow_connections) 
		EXECUTE [dbo].[DBA_getDatabasesMaintenanceList] 

	DECLARE dbs CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
		SELECT db.[name]  
			FROM @db AS db 
				INNER JOIN DBA.dbo.DatabaseInformation AS d 
					ON d.name = db.name COLLATE DATABASE_DEFAULT 
						AND d.server_name = @@SERVERNAME 
			WHERE ISNULL(d.backupBatchNo, 0) = ISNULL(@batchNo, 0) 
				AND SUBSTRING(d.IndexMaintenanceSchedule, @dayOfTheWeek, 1) <> '-' -- Remove one day from @dayOfTheWeek to read the actual position and not from that 
				AND @dbname IS NULL 
				AND db.role = 1 -- primary
		UNION  
		-- Specified database if any 
		SELECT [name]  
			FROM @db AS db 
			WHERE db.name LIKE @dbname 
			ORDER BY [name]  
	OPEN dbs 
	FETCH NEXT FROM dbs INTO @dbname 

	WHILE @@FETCH_STATUS = 0 BEGIN 

		SET @time = GETDATE() 
		PRINT REPLICATE ( CHAR(10), 3 ) + 'Processing database: ' + QUOTENAME(@dbname) + ' @ ' + CONVERT(VARCHAR(20),GETDATE(),120) 

		SET @sqlString = N' 

		USE ' + QUOTENAME(@dbname) + N' 

		DECLARE @oneTab					CHAR(1) = CHAR(9) 
		DECLARE @oneLine				CHAR(1) = CHAR(10) 

		DECLARE @object_id				INT 
		DECLARE @index_id				INT 
		DECLARE @partition_number		INT 
		DECLARE @db_id					INT = DB_ID() 
		DECLARE @dbname					SYSNAME = DB_NAME() 
		DECLARE @action					VARCHAR(20) 
		DECLARE @command				NVARCHAR(MAX) 
		DECLARE @timestamp				DATETIME = GETDATE() 
		DECLARE @ftCatalogName			SYSNAME  

		DECLARE @isEnterprise			BIT = (SELECT CASE WHEN SERVERPROPERTY(''EngineEdition'') = 3 THEN 1 ELSE 0 END) 
										--   If the server engine is not Enterprise, the index cannot be REBUILT ONLINE 

		DECLARE @SQLNumericVersion		INT = (DBA.dbo.getNumericSQLVersion(NULL)) 

		IF OBJECT_ID(''tempdb..#work_to_do'') IS NOT NULL DROP TABLE #work_to_do 

		-- Created table variable to hold finding fragmentation times
		DECLARE @FindingFragmentation table (
			[Action]                     varchar(15)  NOT NULL,
			server_name                  sysname      NOT NULL,
			[database_name]              sysname      NOT NULL,
			database_id                  int          NOT NULL,
			DataCollectionTime           datetime     NOT NULL,
			Duration_seconds             int          NOT NULL
		);

		PRINT @oneLine + N''Finding Fragmentation... ''  

		SELECT	IDENTITY(INT,1,1)												AS ID 
				, @@SERVERNAME													AS [server_name] 
				, CONVERT(VARCHAR(15), '''')									AS [Action] 
				, 0																AS [isOnlineOperation] 
				, QUOTENAME(DB_NAME())											AS [database_name]				 
				, @db_id														AS [database_id]				 
				, fix.[object_id]												AS [object_id] 
				, QUOTENAME(OBJECT_SCHEMA_NAME(fix.object_id))					AS [schema_name] 
				, QUOTENAME(OBJECT_NAME(fix.object_id))							AS [object_name] 
				, fix.index_id													AS [index_id] 
				, fix.partition_number											AS [partition_number] 
				, pc.partition_count											AS [partition_count] 
				, ix.ignore_dup_key												AS [ignore_dup_key] 
				, ix.is_padded													AS [is_padded] 
				, CASE WHEN ix.fill_factor = 0 THEN 100 ELSE ix.fill_factor	END	AS [fill_factor] 
				, p.data_compression_desc COLLATE DATABASE_DEFAULT				AS [data_compression_desc] 
				, fix.avg_fragmentation_in_percent								AS [avg_fragmentation_in_percent] 
				, fix.page_count												AS [page_count] 
				, QUOTENAME(ix.name) 											AS [index_name] 
				, ix.[type]														AS [type] 
				, ix.[type_desc] COLLATE DATABASE_DEFAULT						AS [type_desc] 
				, ix.is_primary_key												AS [is_primary_key] 
				, OBJECTPROPERTY(ix.[object_id], ''IsView'')					AS [IsView] 
				, OBJECTPROPERTY(fix.[object_id], ''IsIndexed'')				AS [IsIndexed] 
				, OBJECTPROPERTY(fix.[object_id], ''ExecIsAnsiNullsOn'')		AS [ExecIsAnsiNullsOn] -- check what happen 
				, ix.allow_row_locks											AS [allow_row_locks] 
				, ix.allow_page_locks											AS [allow_page_locks]	 
				,  
					CASE	 
						WHEN ix.[type] = 1 -- Clustered 
							AND EXISTS (SELECT 1 
											FROM sys.all_columns c 
												INNER JOIN sys.types t 
													ON c.system_type_id = t.system_type_id 
											WHERE c.object_id = @object_id 
												AND ( 
													(@SQLNumericVersion < 11  
														AND ( c.system_type_id IN (34, 35, 99, 241) -- LOBs 
															OR (c.system_type_id IN (165, 167, 231) AND c.max_length = -1 ) ) ) -- (MAX) datatypes 

													-- From 2012 MAX types are allowed for online rebuild 
													OR (@SQLNumericVersion >= 11  
														AND c.system_type_id IN (34, 35, 99, 241)) -- LOBs 
													) 
										)																 
							THEN 1 
						WHEN ix.[type] = 2 -- Non clustered 
							AND EXISTS (SELECT 1 
											FROM sys.index_columns as ixc 
												INNER JOIN sys.all_columns as c 
													ON c.object_id = ix.object_id 
														and c.column_id = ixc.column_id 
											WHERE ixc.object_id = @object_id 
												AND ixc.index_id = @index_id 
												-- From 2012 (MAX) types are allowed to be included in NCIX for online rebuilds,  
												-- LOB types are not allowed in NCIX either as key or included, hence there is no check 
												AND @SQLNumericVersion < 11  
												AND c.system_type_id IN (165, 167, 231) AND c.max_length = -1 -- MAX data types 
										)   

							THEN 1 
						ELSE 0 
					END															AS HasLobData 

				, @timestamp													AS DataCollectionTime 
				, CONVERT(INT, 0)												AS Duration_seconds 

			INTO #work_to_do 
			FROM sys.dm_db_index_physical_stats (@db_id, NULL, NULL , NULL, ''LIMITED'') AS fix 

				INNER JOIN sys.indexes AS ix 
					ON ix.object_id		= fix.object_id 
						AND ix.index_id = fix.index_id	 
				INNER JOIN sys.partitions AS p 
					ON p.object_id				= ix.object_id 
						AND p.index_id			= ix.index_id 
						AND p.partition_number	= fix.partition_number 

				OUTER APPLY (SELECT COUNT(*) AS partition_count FROM sys.partitions AS p WHERE p.object_id = ix.object_id AND p.index_id = ix.index_id) AS pc 

			WHERE fix.index_id > 0 
				AND avg_fragmentation_in_percent IS NOT NULL 
				AND avg_fragmentation_in_percent > @minFragReorganize 
				AND fix.page_count > @minPageCount 

		--SELECT * FROM #work_to_do 
		PRINT N''Time taken: '' + [DBA].[dbo].[formatSecondsToHR](DATEDIFF(ss, @timestamp, GETDATE())) 

		-- Record time taken to find fragmentation
		INSERT INTO @FindingFragmentation (
			[Action],        
			server_name,
			[database_name],
			database_id,
			DataCollectionTime,
			Duration_seconds
		)
		VALUES
			 (''FIND_FRAG'',                                                                  
			  @@SERVERNAME,                             
			  QUOTENAME(DB_NAME()),                     
			  @db_id,                                                                          
			  @timestamp,                               
			  DATEDIFF(SECOND, @timestamp, GETDATE())   
			);

		-- Update Action and   
		UPDATE #work_to_do 
			SET Action				= CASE  
											WHEN (avg_fragmentation_in_percent BETWEEN @minFragReorganize AND @minFragRebuild) 
												OR (HasLobData = 1) 
												OR (IsView = 1 AND IsIndexed = 1 AND ExecIsAnsiNullsOn = 0) 

												THEN ''REORGANIZE'' 
											ELSE 
												''REBUILD'' 
										END 
				, isOnlineOperation = CASE  
											-- Reorganize is always online operation 
											WHEN (avg_fragmentation_in_percent BETWEEN @minFragReorganize AND @minFragRebuild) 
												OR (HasLobData = 1) 
												OR (IsView = 1 AND IsIndexed = 1 AND ExecIsAnsiNullsOn = 0) 

												THEN ''true'' 
											-- When is rebuild, it depends on the engine 
											ELSE 
												@isEnterprise 
										END  

		IF @debugging = 1 BEGIN 
			SELECT  0 AS defaultId,
					ff.server_name,
					ff.Action,
					0,
					ff.database_name,
					ff.database_id,
					N'''',
					N'''',
					N'''',
					0,
					0,
					0,
					0,
					0,
					0,
					NULL,
					0,
					0,
					N'''',
					0,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					NULL,
					0,
					ff.DataCollectionTime,
					ff.Duration_seconds
			FROM    @FindingFragmentation AS ff
			UNION ALL
			SELECT  wtd.ID,
					wtd.server_name,
					wtd.Action,
					wtd.isOnlineOperation,
					wtd.database_name,
					wtd.database_id,
					wtd.object_id,
					wtd.schema_name,
					wtd.object_name,
					wtd.index_id,
					wtd.partition_number,
					wtd.partition_count,
					wtd.ignore_dup_key,
					wtd.is_padded,
					wtd.fill_factor,
					wtd.data_compression_desc,
					wtd.avg_fragmentation_in_percent,
					wtd.page_count,
					wtd.index_name,
					wtd.type,
					wtd.type_desc,
					wtd.is_primary_key,
					wtd.IsView,
					wtd.IsIndexed,
					wtd.ExecIsAnsiNullsOn,
					wtd.allow_row_locks,
					wtd.allow_page_locks,
					wtd.HasLobData,
					wtd.DataCollectionTime,
					wtd.Duration_seconds
			FROM    #work_to_do AS wtd;
		END 

		DECLARE cur CURSOR FORWARD_ONLY READ_ONLY FAST_FORWARD FOR  
		SELECT  
				i.Action 
				-- Actual statement we will apply to the index 
				, N''ALTER INDEX '' + i.index_name + N'' ON '' + i.schema_name + N''.'' + i.object_name +  
					CASE  
						WHEN (i.avg_fragmentation_in_percent BETWEEN @minFragReorganize AND @minFragRebuild) 
							OR (i.HasLobData = 1) 
							OR (i.IsView = 1 AND i.IsIndexed = 1 AND i.ExecIsAnsiNullsOn = 0) 

							THEN N'' REORGANIZE'' + CASE WHEN [partition_count] > 1 THEN N'' PARTITION = '' + CONVERT(NVARCHAR, [partition_number]) ELSE '''' END 

						WHEN i.[partition_count] > 1  
							THEN 
						-- Rebuild partition 
							N'' REBUILD PARTITION = '' + CONVERT(NVARCHAR, [partition_number]) + N'' WITH (SORT_IN_TEMPDB = ON'' +   
										N'', MAXDOP = ''				+ CONVERT(NVARCHAR, @maxdop) + 
										N'', DATA_COMPRESSION = ''	+ data_compression_desc + 
										N'', ONLINE = ''				+ CASE WHEN isOnlineOperation = 1	THEN N''ON'' ELSE N''OFF'' END + '')''					 

							ELSE 
						-- Rebuild index 
							N'' REBUILD WITH (PAD_INDEX = ''			+ CASE WHEN is_padded = 1			THEN N''ON'' ELSE N''OFF'' END	+  
										N'', FILLFACTOR = ''			+ CONVERT(NVARCHAR, i.fill_factor)								+ 
										N'', SORT_IN_TEMPDB = ON''																	+ 
										--------------------Pointless... you cannot add this parameter for primary keys or unique indexes... 
										--------------------CASE WHEN i.[is_primary_key] = 1 THEN '''' ELSE -- this option cannot be specified for primary keys, regardless is ON or OFF 
										--------------------	N'', IGNORE_DUP_KEY = ''		+ CASE WHEN ignore_dup_key = 1		THEN N''ON'' ELSE N''OFF'' END 
										--------------------END	+ 
										N'', ONLINE = ''				+ CASE WHEN isOnlineOperation = 1	THEN N''ON'' ELSE N''OFF'' END	+  
										N'', ALLOW_ROW_LOCKS = ''		+ CASE WHEN [allow_row_locks] = 1	THEN N''ON'' ELSE N''OFF'' END	+  
										N'', ALLOW_PAGE_LOCKS = ''	+ CASE WHEN [allow_page_locks] = 1	THEN N''ON'' ELSE N''OFF'' END	+  
										N'', MAXDOP = ''				+ CONVERT(NVARCHAR, @maxdop)									+ 
										N'', DATA_COMPRESSION = ''	+ data_compression_desc											+ 
										N'', FILLFACTOR = ''			+ CONVERT(NVARCHAR, i.fill_factor) +'')'' 

					END AS [REORGANIZE_REBUILD] 

				, i.object_id 
				, i.index_id 
				, i.partition_number
			FROM #work_to_do AS i 

		OPEN cur 
		FETCH NEXT FROM cur INTO @action, @command, @object_id, @index_id, @partition_number

		WHILE @@FETCH_STATUS = 0 BEGIN 

			SET @timestamp = GETDATE() 

			PRINT N''Executing: '' + @command 

				BEGIN TRY  

					-- Persist index usage information as some SQL versions might lose it 
					EXECUTE DBA.dbo.DBA_indexUsageStatsPersistsHistory 
							@dbname			= @dbname 
							, @object_id	= @object_id 
							, @index_id		= @index_id 
							, @debugging	= @debugging 

					IF @debugging = 0 BEGIN 
						EXECUTE sp_executesql @command 
					END 

					UPDATE #work_to_do  
						SET Duration_seconds = DATEDIFF(SECOND,@timestamp, GETDATE()) 
						WHERE database_id = @db_id 
							AND object_id = @object_id 
							AND index_id = @index_id 
							AND partition_number = @partition_number


					PRINT N''Executed - Time taken: '' + [DBA].[dbo].[formatSecondsToHR](DATEDIFF(ss, @timestamp, GETDATE())) 

					-- Backup the transaction log (if required) 
					EXECUTE DBA.dbo.DBA_runLogBackup @dbname = @dbname, @skipUsageValidation = 0, @debugging = @debugging 

				END TRY 
				BEGIN CATCH 
					SELECT ERROR_MESSAGE(), ERROR_NUMBER() 

				END CATCH 

				FETCH NEXT FROM cur INTO @action, @command, @object_id, @index_id, @partition_number 

		END 

		CLOSE cur 
		DEALLOCATE cur 

		-- Check for fulltext catalogs  
		DECLARE cur CURSOR FORWARD_ONLY READ_ONLY FAST_FORWARD FOR  
			SELECT c.Name AS FullTextCatalogName 
				FROM sys.fulltext_catalogs c 
					INNER JOIN sys.fulltext_indexes i 
						ON i.fulltext_catalog_id = c.fulltext_catalog_id 
					INNER JOIN sys.fulltext_index_fragments f 
						ON f.table_id = i.object_id  
				GROUP BY c.Name 
				HAVING COUNT(*) > 1000000000 -- disable the ft rebuild for now (21/02/2017)

		OPEN cur 
		FETCH NEXT FROM cur INTO @ftCatalogName 

		WHILE @@FETCH_STATUS = 0 BEGIN 

				SET @command = ''ALTER FULLTEXT CATALOG '' + QUOTENAME(@ftCatalogName) + '' REBUILD'' 
				SELECT @timestamp = GETDATE() 

				BEGIN TRY 

					PRINT @oneTab + N''Executing: '' + @command 

					IF @debugging = 0 BEGIN 
						EXECUTE sp_executesql @command 
					END 

					PRINT @oneTab + N''Executed - Time taken: '' + [DBA].[dbo].[formatSecondsToHR](DATEDIFF(ss, @timestamp, GETDATE())) 

					EXECUTE DBA.dbo.DBA_runLogBackup @dbname = @dbname, @skipUsageValidation = 0, @debugging = @debugging 

				END TRY 
				BEGIN CATCH 
				END CATCH 

			FETCH NEXT FROM cur INTO @ftCatalogName 

		END 

		CLOSE cur 
		DEALLOCATE cur 

		IF @debugging = 0 BEGIN 
		-- Save  
			INSERT INTO DBA.dbo.IndexFragmentationHistory 
					([Action],[isOnlineOperation],[server_name],[database_name],[database_id],[object_id] 
					,[schema_name],[object_name],[index_id] 
					,[partition_number],[partition_count],[ignore_dup_key],[is_padded],[fill_factor],[data_compression_desc] 
					,[avg_fragmentation_in_percent],[page_count],[index_name],[type],[type_desc],[is_primary_key],[IsView],[IsIndexed] 
					,[ExecIsAnsiNullsOn],[allow_row_locks],[allow_page_locks],[HasLobData],[DataCollectionTime],[Duration_seconds]) 

			SELECT [Action],0,[server_name],DBA.dbo.UNQUOTENAME([database_name]),[database_id],0,N'''',N'''',0,0,0,0,0,0,NULL,0,0,N'''',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,0,[DataCollectionTime],[Duration_seconds] 
				FROM @FindingFragmentation 

			INSERT INTO DBA.dbo.IndexFragmentationHistory 
					([Action],[isOnlineOperation],[server_name],[database_name],[database_id],[object_id] 
					,[schema_name],[object_name],[index_id] 
					,[partition_number],[partition_count],[ignore_dup_key],[is_padded],[fill_factor],[data_compression_desc] 
					,[avg_fragmentation_in_percent],[page_count],[index_name],[type],[type_desc],[is_primary_key],[IsView],[IsIndexed] 
					,[ExecIsAnsiNullsOn],[allow_row_locks],[allow_page_locks],[HasLobData],[DataCollectionTime],[Duration_seconds]) 

			SELECT [Action],[isOnlineOperation],[server_name],DBA.dbo.UNQUOTENAME([database_name]),[database_id],[object_id] 
					,DBA.dbo.UNQUOTENAME([schema_name]),DBA.dbo.UNQUOTENAME([object_name]),[index_id] 
					,[partition_number],[partition_count],[ignore_dup_key],[is_padded],[fill_factor],[data_compression_desc] 
					,[avg_fragmentation_in_percent],[page_count],DBA.dbo.UNQUOTENAME([index_name]),[type],[type_desc],[is_primary_key],[IsView],[IsIndexed] 
					,[ExecIsAnsiNullsOn],[allow_row_locks],[allow_page_locks],[HasLobData],[DataCollectionTime],[Duration_seconds] 
				FROM #work_to_do 
		END 

		' 
		IF @debugging = 1 BEGIN 
			SELECT CONVERT(XML, '<?query --' + @sqlString + '--?>') 
		END 

		EXECUTE sp_executesql @stmt = @sqlString 
				, @params = N'@debugging BIT, @maxdop INT, @minFragReorganize FLOAT, @minFragRebuild FLOAT, @minPageCount BIGINT' 
				, @debugging = @debugging  
				, @maxdop = @maxdop  
				, @minFragReorganize = @minFragReorganize  
				, @minFragRebuild = @minFragRebuild 
				, @minPageCount = @minPageCount  

		PRINT REPLICATE ( CHAR(10), 3 ) + 'Finishing Database : ' + QUOTENAME(@dbname) + ' @ ' + CONVERT(VARCHAR(20),GETDATE(),120) 
		PRINT REPLICATE ( CHAR(10), 3 ) + 'Time Taken         : ' + DBA.dbo.formatSecondsToHR(DATEDIFF(SECOND, @time, GETDATE() )) 

		FETCH NEXT FROM dbs INTO @dbname 

	END 

	CLOSE dbs 
	DEALLOCATE dbs 
END  



GO
