SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON 
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
-- Create date: 17/07/2013 
-- Description:	Returns descriptive information for a database, schema or table specified. 
-- 
-- Assupmtions:	Depending on the user executing the SP, the metadata displayed can vary 
--				User 'reporting' is granted with view definition permission to guarantee all info is complete in the report server 
-- 
-- Change Log:	24/09/2013	RAG	- Added column row_count for tables 
--				25/10/2013	RAG	- Changed the calculation of row_count and added TotalSpaceMB, UsedSpaceMB and UnusedSpaceMB for tables 
--				28/10/2013	RAG	- Added filter to not process Objects created by an internal SQL Server component (is_ms_shipped = 0) 
--				29/10/2013	RAG	- Added parameter column name, if provided, only tables which match the column name will appear on the list 
--				29/10/2013	RAG	- @tableName and @columnName can come with wildcards as the comparison use LIKE  
--				29/10/2013	RAG	- included column Collation  
--				14/11/2013	RAG	- Changed the comparison of database name to like, this way we can call the SP with database name 'dbName%' 
--				02/12/2013	RAG	- Added column IsIdentity 
--				11/12/2013	RAG	- Added a new resultset for when @columnName is specified 
--				13/12/2013	RAG	- Added a DataSpace column 
--				28/02/2014	RAG	- Change on how data sizes are calculated to get same results as Table - properties - storage, also included Index Size 
--				29/10/2014	RAG	- Added Columns LastUserAccess and TotalUserAccess aggregating data from sys.dm_db_index_usage_stats 
--				09/03/2015	RAG	- Added Columns tableType, HEAP or CLUSTERED 
--				30/03/2015	RAG	- Changed the way of counting rows to consider partitioned tables 
--				01/05/2015	RAG	- Use total_pages to calculate total size 
--				22/03/2016	RAG	- Added indexed views to the results 
--									Create temp table for columns using SELECT INTO as it is shorter and have the same definition 
--				13/04/2016	RAG	- Changed the way [IndexSpaceUsed] is calculated to display total size of non clustered indexes 
--				14/07/2016	SZO	- Removed no longer necessary comments from the code block. 
--				04/10/2016	RAG	- Changes due to case sensitivity (column definition) 
--				15/02/2017	RAG	- Changed table type to include Clustered columnstore by getting indexes.type_desc instead of hardcoded HEAP and CLUSTERED 
--				14/01/2021	RAG	- Added parameter @EngineEdition
--				21/01/2021	RAG	- Added whether the Primary Key is clustered or not
--				22/01/2021	RAG	- Added parameter @sortOrder with the possible values NULL (alphabetically), size (In MB desc), row_count (desc)
--									Only aplies for @onlyTablesList = 1
--				03/02/2021	RAG	- Added columns
-- 									- IN_ROW_DATA_MB
--									- LOB_DATA_MB		
--									- ROW_OVERFLOW_DATA_MB	
--				17/02/2021	RAG	- Fixed collation issues
--				11/04/2021	RAG	- Changes
--									- Split Last User Access into Last Write / Last Read
--									- Split Total User Access into User Writes / User Reads
--				21/10/2021	RAG	- Add FK DELETE and UPDATE actions
----------------------------------------------------------------------------------------
--				 
-- ============================================= 
GO

DECLARE 
	@dbname				SYSNAME = NULL
	, @schemaName		SYSNAME = NULL
	, @tableName		SYSNAME = NULL
	, @columnName		SYSNAME = NULL
	, @onlyTablesList	BIT		= 1
	, @sortOrder		SYSNAME = NULL

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

DECLARE @EngineEdition	INT	= CONVERT(INT, SERVERPROPERTY('EngineEdition'))
DECLARE @numericVersion INT = CONVERT(INT, PARSENAME(CONVERT(SYSNAME, SERVERPROPERTY('ProductVersion')),4))

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

IF @columnName IS NOT NULL BEGIN SET @onlyTablesList = 0 END 

IF OBJECT_ID('tempdb..#resultTables') 		IS NOT NULL DROP TABLE #resultTables 
IF OBJECT_ID('tempdb..#resultColumns') 		IS NOT NULL DROP TABLE #resultColumns 
IF OBJECT_ID('tempdb..#db_triggers') 		IS NOT NULL DROP TABLE #db_triggers 
IF OBJECT_ID('tempdb..#index_usage_stats') 	IS NOT NULL DROP TABLE #index_usage_stats 
IF OBJECT_ID('tempdb..#table_storage') 		IS NOT NULL DROP TABLE #table_storage

CREATE TABLE #resultTables 
	( databaseName			SYSNAME			NULL 
	, schemaName			SYSNAME			NULL 
	, tableName				SYSNAME			NULL 
	, tableType				SYSNAME			NULL 
	, row_count				BIGINT			NULL 
	, TotalSpaceMB			DECIMAL(15,3)	NULL 
	, DataSpaceMB			DECIMAL(15,3)	NULL 
	, IndexSpaceMB			DECIMAL(15,3)	NULL 
	, UnusedSpaceMB			DECIMAL(15,3)	NULL 
	, IN_ROW_DATA_MB		DECIMAL(15,3)	NULL
	, LOB_DATA_MB			DECIMAL(15,3)	NULL
	, ROW_OVERFLOW_DATA_MB	DECIMAL(15,3)	NULL
	, TableTriggers			VARCHAR(500)	NULL 
	, LastUserRead			DATETIME		NULL 
	, LastUserUpdate		DATETIME		NULL 
	, UserReads				BIGINT			NULL 
	, UserUpdates			BIGINT			NULL 
	, LastUserLookup		DATETIME		NULL 
	, Column_id				INT				NULL 
	, columnName			SYSNAME			NULL 
	, DataType				SYSNAME			NULL 
	, Size					VARCHAR(30)		NULL 
	, IsIdentity			VARCHAR(3)		NULL 
	, Mandatory				VARCHAR(3)		NULL 
	, DefaultValue			NVARCHAR(MAX)	NULL 
	, PrimaryKey			VARCHAR(30)		NULL 
	, ForeignKey			VARCHAR(3)		NULL 
	, IsComputed			VARCHAR(3)		NULL 
	, Collation				SYSNAME			NULL 
	, [definition]			NVARCHAR(MAX)	NULL 
	, Filestream			VARCHAR(3)		NULL 
	, ReferencedColumn		NVARCHAR(256)	NULL 
	, TableDescription		SQL_VARIANT		NULL 
	, ColDescription		SQL_VARIANT		NULL) 
	
SELECT *  
	INTO #resultColumns 
	FROM #resultTables 
	WHERE 1=0 

CREATE TABLE #db_triggers ( 
parent_id			INT 
, trigger_type		NVARCHAR(4000)) 
	
CREATE TABLE #index_usage_stats ( 
object_id			INT 
, last_user_read	DATETIME	NULL
, last_user_update	DATETIME	NULL
, user_reads		BIGINT		NULL
, user_updates		BIGINT		NULL) 

CREATE TABLE #table_storage(
[object_id]					INT NOT NULL
, [index_id]				INT NOT NULL
, [row_count]				BIGINT NOT NULL
, [TotalSpaceUsed]			DECIMAL(15,3)
, [DataSpaceUsed]			DECIMAL(15,3)
, [IndexSpaceUsed]			DECIMAL(15,3)
, [UnusedSpace]				DECIMAL(15,3)
, [IN_ROW_DATA_MB]			DECIMAL(15,3)
, [LOB_DATA_MB]				DECIMAL(15,3)
, [ROW_OVERFLOW_DATA_MB]	DECIMAL(15,3)
)

DECLARE @databases TABLE  
	( ID				INT IDENTITY 
	, dbname			SYSNAME) 
		
DECLARE @sqlstring		NVARCHAR(MAX) 
		, @countDBs		INT = 1 
		, @numDBs		INT 

INSERT INTO @databases  
	SELECT TOP 100 PERCENT name  
		FROM sys.databases  
		WHERE [name] NOT IN ('model', 'tempdb')  
			AND state = 0  
			AND name LIKE ISNULL(@dbname, name) 
		ORDER BY name ASC		 

SET @numDBs = @@ROWCOUNT 

WHILE @countDBs <= @numDBs BEGIN 
		
	SELECT @dbname = dbname  
		FROM @databases 
		WHERE ID = @countDBs 

	SET @sqlstring = CASE WHEN @EngineEdition <> 5 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
		+ CONVERT(NVARCHAR(MAX), N'
		SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
		
		TRUNCATE TABLE #db_triggers 
		TRUNCATE TABLE #index_usage_stats 
		TRUNCATE TABLE #table_storage 

		INSERT INTO #db_triggers 
		SELECT parent_id 
				, name + '' ('' + 
					CASE WHEN tr.is_instead_of_trigger = 1 THEN ''INSTEAD OF '' ELSE ''AFTER '' END + 
					STUFF( (SELECT '', '' + type_desc FROM sys.trigger_events AS tre WHERE tre.object_id = tr.object_id ORDER BY type_desc ASC FOR XML PATH('''')  ),1, 2, '''') + 
					CASE WHEN tr.is_disabled = 1 THEN '' (Disabled)'' ELSE '''' END + '')'' 
					AS trigger_type				 
			FROM sys.triggers AS tr 
			WHERE OBJECT_SCHEMA_NAME(parent_id) = ISNULL(@schemaName COLLATE DATABASE_DEFAULT, OBJECT_SCHEMA_NAME(parent_id)) 
				AND OBJECT_NAME(parent_id) LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, OBJECT_NAME(parent_id))

		INSERT INTO #index_usage_stats 
			SELECT object_id
					, MAX(last_user_read) AS last_user_read
					, MAX(last_user_update) AS last_user_update
					, SUM(user_reads) AS user_reads
					, SUM(user_updates) AS user_updates
			FROM (
				SELECT object_id
					, ( ius.user_scans + ius.user_seeks + ius.user_lookups ) AS user_reads
					, ius.user_updates
					, (SELECT MAX(v) FROM (VALUES([last_user_lookup]), ([last_user_scan]), ([last_user_seek])) t(v)) AS last_user_read
					, ISNULL(ius.last_user_update, 0) AS last_user_update
				FROM sys.dm_db_index_usage_stats AS ius 
							WHERE database_id = DB_ID() 
								AND OBJECT_SCHEMA_NAME(ius.object_id) = ISNULL(@schemaName COLLATE DATABASE_DEFAULT, OBJECT_SCHEMA_NAME(ius.object_id)) 
								AND OBJECT_NAME(ius.object_id) LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, OBJECT_NAME(ius.object_id)) 
			) AS t
			GROUP BY object_id

		INSERT INTO #table_storage
		SELECT object_id
					, index_id
					, SUM(row_count)						AS row_count
					, SUM([TotalSpaceUsed])					AS [TotalSpaceUsed]
					, SUM([DataSpaceUsed])					AS [DataSpaceUsed]
					, SUM([IndexSpaceUsed])					AS [IndexSpaceUsed]
					, SUM([UnusedSpace])					AS [UnusedSpace]
					, ISNULL(MAX([IN_ROW_DATA])		, 0)	AS [IN_ROW_DATA_MB]
					, ISNULL(MAX([LOB_DATA])		, 0)	AS [LOB_DATA_MB]
					, ISNULL(MAX([ROW_OVERFLOW_DATA]), 0)	AS [ROW_OVERFLOW_DATA_MB]
			FROM  (
				
				(SELECT i.object_id
							, i.index_id
							, a.type_desc AS allocation_unit_type_desc
							, SUM(CASE WHEN a.type = 1 THEN p.rows ELSE 0 END) AS row_count
							, CONVERT( DECIMAL(15,3), ISNULL( (8.000000 * SUM(a.total_pages)) / 1024 , 0 ) ) AS [TotalSpaceUsed] 
							, CONVERT( DECIMAL(15,3), ISNULL( (8.000000 * SUM(               CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) ) AS [DataSpaceUsed] 
							-- wrong calculation, use OUTER APPLY 
							--, CONVERT( DECIMAL(15,3), ISNULL( (8.000000 * SUM(a.used_pages - CASE WHEN a.type <> 1 THEN a.used_pages WHEN p.index_id < 2 THEN a.data_pages ELSE 0 END)) / 1024 , 0 ) ) AS [IndexSpaceUsed] 
							, CONVERT( DECIMAL(15,3), ixsp.[IndexSpaceUsed] / 1024. ) AS [IndexSpaceUsed] 
							, CONVERT( DECIMAL(9,2), ((SUM(a.total_pages) - SUM(a.used_pages)) * 8 / 1024.) )  AS UnusedSpace 
							, CONVERT(DECIMAL(15,3), SUM(a.total_pages) / 128.) AS size_mb
						FROM sys.indexes AS i
							INNER JOIN sys.partitions AS p 
								ON p.object_id = i.object_id 
									AND p.index_id = i.index_id 
							INNER JOIN sys.allocation_units AS a  
								ON a.container_id = p.partition_id  
							OUTER APPLY (
								SELECT  
							 
										CASE WHEN (tbl.is_memory_optimized=0) THEN  
											ISNULL(( 
											(SELECT SUM (used_page_count) FROM sys.dm_db_partition_stats ps WHERE ps.object_id = tbl.object_id) 
											+ ( CASE (SELECT count(*) FROM sys.internal_tables WHERE parent_id = tbl.object_id AND internal_type IN (202,204,207,211,212,213,214,215,216,221,222)) 
												WHEN 0 THEN 0 
												ELSE ( 
													SELECT sum(p.used_page_count) 
													FROM sys.dm_db_partition_stats p, sys.internal_tables it 
													WHERE it.parent_id = tbl.object_id AND it.internal_type IN (202,204,207,211,212,213,214,215,216,221,222) AND p.object_id = it.object_id) 
												END ) 
											- (SELECT SUM (CASE WHEN(index_id < 2) THEN (in_row_data_page_count + lob_used_page_count + row_overflow_used_page_count) ELSE 0 END) 
												FROM sys.dm_db_partition_stats WHERE object_id = tbl.object_id) 
											) * 8, 0.0) 
						 
										ELSE 
											ISNULL((SELECT (tms.[memory_used_by_indexes_kb]) 
											FROM [sys].[dm_db_xtp_table_memory_stats] tms 
											WHERE tms.object_id = tbl.object_id), 0.0) 
										END AS [IndexSpaceUsed]
									FROM sys.tables AS tbl 
									WHERE tbl.object_id = i.object_id 
							) AS ixsp  
						WHERE OBJECT_SCHEMA_NAME(i.object_id) = ISNULL(@schemaName COLLATE DATABASE_DEFAULT, OBJECT_SCHEMA_NAME(i.object_id)) 
							AND OBJECT_NAME(i.object_id) LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, OBJECT_NAME(i.object_id))
							AND i.index_id IN (0,1)
						GROUP BY i.object_id
								, i.index_id
								, a.type_desc
								, ixsp.[IndexSpaceUsed]
					)
			
			) AS npvt
			PIVOT (MAX(size_mb) FOR allocation_unit_type_desc IN ([IN_ROW_DATA], [LOB_DATA], [ROW_OVERFLOW_DATA])) AS pvt
		GROUP BY object_id
					, index_id


		INSERT INTO #resultTables 
				(databaseName 
				, schemaName 
				, tableName 
				, tableType 
				, row_count 
				, TotalSpaceMB 
				, DataSpaceMB 
				, IndexSpaceMB 
				, UnusedSpaceMB 
				, IN_ROW_DATA_MB		
				, LOB_DATA_MB			
				, ROW_OVERFLOW_DATA_MB	
				, Column_id 
				, TableDescription 
				, TableTriggers 
				, LastUserRead		
				, LastUserUpdate	
				, UserReads	
				, UserUpdates) 
		SELECT DB_NAME() 
				, OBJECT_SCHEMA_NAME(i.object_id)  
				, OBJECT_NAME(i.object_id)  
				, CASE  
						WHEN OBJECTPROPERTYEX(i.object_id, ''IsView'') = 1 THEN ''INDEXED VIEW''  
						ELSE i.type_desc 
					END AS tableType  

				, ts.row_count
				, ts.TotalSpaceUsed
				, ts.DataSpaceUsed
				, ts.IndexSpaceUsed
				, ts.UnusedSpace
				, ts.IN_ROW_DATA_MB		
				, ts.LOB_DATA_MB			
				, ts.ROW_OVERFLOW_DATA_MB	
				, 0 AS [Column_id]
				, xp.value AS [TableDescription]
				, STUFF( (SELECT '', '' + trigger_type FROM #db_triggers AS tr WHERE tr.parent_id = i.object_id FOR XML PATH('''')  ),1, 2, '''')  AS [triggers]
				, ius.last_user_read 
				, ius.last_user_update 
				, user_reads
				, user_updates
			FROM sys.indexes AS i  
				LEFT JOIN sys.extended_properties AS xp 
					ON xp.major_id = i.object_id 
						AND xp.minor_id = 0 
						AND xp.name = ''MS_Description'' 
				LEFT JOIN #table_storage as ts
					ON ts.objecT_id = i.object_id
						AND ts.index_id = i.index_id
				LEFT JOIN #index_usage_stats AS ius 
					ON ius.object_id = i.object_id  
			WHERE OBJECTPROPERTYEX(i.object_id, ''IsMSShipped'') = 0 
				AND i.index_id IN (0, 1) -- Heap or Clustered 
				AND OBJECT_SCHEMA_NAME(i.object_id) = ISNULL(@schemaName COLLATE DATABASE_DEFAULT, OBJECT_SCHEMA_NAME(i.object_id))
				AND OBJECT_NAME(i.object_id) LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, OBJECT_NAME(i.object_id))
	') 
	-- SELECT @sqlstring
	-- Insert all tables with their descriptions 
	EXECUTE sp_executesql 
				@stmt = @sqlstring
				, @params = N'@schemaName SYSNAME, @tableName SYSNAME'
				, @schemaName = @schemaName  
				, @tableName = @tableName 
	
	IF @onlyTablesList = 0 BEGIN  

		SET @sqlstring = CASE WHEN @EngineEdition <> 8 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
			+ CONVERT(NVARCHAR(MAX), N'
			
			INSERT INTO #resultColumns 
					(databaseName 
					, schemaName 
					, tableName 
					, Column_id 
					, columnName 
					, DataType 
					, Size 
					, IsIdentity 
					, Mandatory 
					, DefaultValue 
					, PrimaryKey 
					, ForeignKey 
					, IsComputed 
					, Collation 
					, [definition] 
					, Filestream 
					, ReferencedColumn 
					, TableDescription 
					, ColDescription) 
			SELECT DB_NAME() 
					, OBJECT_SCHEMA_NAME(i.object_id) 
					, OBJECT_NAME(i.object_id) 
					, c.column_id 
					, c.name 
					, UPPER(ty.name) 
					, CASE  
							WHEN ty.user_type_id IN (165,167,231) AND c.max_length = -1 THEN ''Unlimited'' 
							WHEN ty.user_type_id IN (231,239) THEN CONVERT(VARCHAR,c.max_length/2) 
							WHEN ty.user_type_id IN (165,167,173,175,231,239) THEN CONVERT(VARCHAR,c.max_length) 
							ELSE '''' 
						END 
					, CASE WHEN c.is_identity = 1 THEN ''Yes''  
							ELSE '''' 
						END 
					, CASE  
							WHEN c.is_nullable = 1 THEN ''No''  
							ELSE ''Yes'' 
						END 
					, CASE  
							WHEN df.definition IS NOT NULL THEN SUBSTRING(df.definition, 2, LEN(df.definition)-2) -- to remove extra parenthesis 
							ELSE '''' 
						END 
					, (SELECT ''Yes (''  + CASE WHEN ix.type > 1 THEN ''Non-'' ELSE '''' END + ''Clustered)''
											FROM sys.index_columns AS ixc  
												LEFT JOIN sys.indexes AS ix 
													ON ix.object_id = i.object_id 
														AND ix.index_id = ixc.index_id 
											WHERE ixc.object_id = i.object_id  
												AND ixc.column_id = c.column_id  
												AND ix.is_primary_key = 1 ) 
					, CASE  
							WHEN fk.object_id IS NOT NULL THEN ''Yes'' 
							ELSE '''' 
						END 
					, CASE  
						WHEN c.is_computed = 1 THEN ''Yes''  
						ELSE '''' 
					END 
					, c.Collation_name 
					, cc.definition 
					, CASE  
						WHEN c.is_filestream = 1 THEN ''Yes''  
						ELSE '''' 
					END 
					, ISNULL(OBJECT_SCHEMA_NAME(rc.object_id) + ''.'' + OBJECT_NAME(rc.object_id) + ''.'' + rc.name 
						+ '' (ON DELETE: '' + fk.delete_referential_action_desc COLLATE DATABASE_DEFAULT
						+ '', ON UPDATE: '' + fk.update_referential_action_desc COLLATE DATABASE_DEFAULT + '')'', '''') 
					, NULL 
					, xp.value 
				FROM sys.indexes AS i 
					INNER JOIN sys.columns AS c 
						ON c.object_id = i.object_id 
							AND i.index_id IN (0,1) 
					LEFT JOIN sys.types AS ty 
						ON ty.user_type_id = c.user_type_id 
					LEFT JOIN sys.default_constraints AS df 
						ON df.parent_object_id = c.object_id 
							AND df.parent_column_id = c.column_id 
					LEFT JOIN sys.computed_columns AS cc 
						ON cc.object_id = i.object_id 
							AND cc.column_id = c.column_id 
					LEFT JOIN sys.foreign_key_columns AS fkc 
						ON fkc.parent_object_id = c.object_id 
							AND fkc.parent_column_id = c.column_id 
					LEFT JOIN sys.foreign_keys AS fk 
						ON fk.object_id = fkc.constraint_object_id 
					LEFT JOIN sys.columns AS rc 
						ON rc.object_id = fkc.referenced_object_id 
							AND rc.column_id = fkc.referenced_column_id 
					LEFT JOIN sys.extended_properties AS xp 
						ON xp.major_id = i.object_id 
							AND xp.minor_id = c.column_id  
							AND xp.name = ''MS_Description'' 
				WHERE OBJECTPROPERTYEX(i.object_id, ''IsMSShipped'') = 0 
					AND OBJECT_SCHEMA_NAME(i.object_id) = ISNULL(@schemaName COLLATE DATABASE_DEFAULT, OBJECT_SCHEMA_NAME(i.object_id)) 
					AND OBJECT_NAME(i.object_id) LIKE ISNULL(@tableName COLLATE DATABASE_DEFAULT, OBJECT_NAME(i.object_id)) 
					AND c.name LIKE ISNULL(@columnName COLLATE DATABASE_DEFAULT, c.name) 
		')
		PRINT @sqlstring 
		-- Insert all Columns for all tables			 
		EXECUTE sp_executesql 
				@stmt = @sqlstring
				, @params = N'@schemaName SYSNAME, @tableName SYSNAME, @columnName SYSNAME'
				, @schemaName = @schemaName  
				, @tableName = @tableName 
				, @columnName = @columnName 
		END -- IF @onlyTablesList = 0  

	SET @countDBs += 1	 
END 


IF @onlyTablesList = 1 BEGIN 
	SELECT ISNULL(databaseName,'') AS databaseName 
			, ISNULL(schemaName,'') AS schemaName 
			, ISNULL(tableName,'') AS tableName 
			, ISNULL(tableType,'') AS tableType 
			, ISNULL(CONVERT(VARCHAR,row_count), '') AS row_count 
			, ISNULL(CONVERT(VARCHAR,TotalSpaceMB), '') AS TotalSpaceMB 
			, ISNULL(CONVERT(VARCHAR,DataSpaceMB), '') AS DataSpaceMB 
			, ISNULL(CONVERT(VARCHAR,IndexSpaceMB), '') AS IndexSpaceMB 
			, ISNULL(CONVERT(VARCHAR,UnusedSpaceMB), '') AS UnusedSpaceMB 
			, ISNULL(CONVERT(VARCHAR,IN_ROW_DATA_MB), '') AS IN_ROW_DATA_MB 
			, ISNULL(CONVERT(VARCHAR,LOB_DATA_MB), '') AS LOB_DATA_MB 
			, ISNULL(CONVERT(VARCHAR,ROW_OVERFLOW_DATA_MB), '') AS ROW_OVERFLOW_DATA_MB 
			, ISNULL(CONVERT(VARCHAR,LastUserRead, 113), '') AS LastUserRead 
			, ISNULL(CONVERT(VARCHAR,LastUserUpdate, 113), '') AS LastUserUpdate 
			, ISNULL(CONVERT(VARCHAR,UserReads), '') AS UserReads
			, ISNULL(CONVERT(VARCHAR,UserUpdates), '') AS UserUpdates
			, ISNULL(TableTriggers,'') AS TableTriggers 
			, ISNULL(TableDescription,'') AS TableDescription 
		FROM #resultTables  AS r
		ORDER BY 
				CASE WHEN @sortOrder = 'size' THEN r.TotalSpaceMB 
					WHEN @sortOrder = 'row_count' THEN r.row_count 
				ELSE NULL END DESC
				, databaseName 
				, schemaName 
				, tableName 
END  
ELSE BEGIN 

-- Delete tables where the columName provided was not found 
	DELETE rt 
		FROM #resultTables AS rt 
			LEFT JOIN #resultColumns AS rc 
				ON rc.databaseName = rt.databaseName 
					AND rc.tableName = rt.tableName 
		WHERE rc.databaseName IS NULL 
			AND ISNULL(@columnName, '') <> '' 

	--IF @columnName IS NULL BEGIN 
		;WITH cte AS( 
			SELECT databaseName 
					, schemaName 
					, tableName 
					, tableType 
					, row_count 
					, TotalSpaceMB 
					, DataSpaceMB 
					, IndexSpaceMB 
					, UnusedSpaceMB 
					, IN_ROW_DATA_MB		
					, LOB_DATA_MB			
					, ROW_OVERFLOW_DATA_MB	
					, UserReads
					, UserUpdates
					, LastUserRead
					, LastUserUpdate
					, TableTriggers 
					, columnName 
					, Column_id 
					, DataType 
					, Size 
					, IsIdentity 
					, Mandatory 
					, DefaultValue 
					, PrimaryKey 
					, IsComputed 
					, Collation 
					, [definition] 
					, ForeignKey 
					, ReferencedColumn 
					, [Filestream]			 
					, TableDescription 
					, ColDescription 
				FROM #resultTables 
			UNION ALL 
			SELECT databaseName 
					, schemaName 
					, tableName 
					, tableType 
					, row_count 
					, TotalSpaceMB 
					, DataSpaceMB 
					, IndexSpaceMB 
					, UnusedSpaceMB 
					, IN_ROW_DATA_MB		
					, LOB_DATA_MB			
					, ROW_OVERFLOW_DATA_MB	
					, UserReads
					, UserUpdates
					, LastUserRead
					, LastUserUpdate
					, TableTriggers 
					, columnName 
					, Column_id 
					, DataType 
					, Size 
					, IsIdentity 
					, Mandatory 
					, DefaultValue 
					, PrimaryKey 
					, IsComputed 
					, Collation 
					, [definition] 
					, ForeignKey 
					, ReferencedColumn 
					, [Filestream] 
					, TableDescription 
					, ColDescription 
				FROM #resultColumns 
		) 
		SELECT ISNULL(databaseName,'') AS databaseName 
				, ISNULL(schemaName,'') AS schemaName 
				, ISNULL(tableName,'') AS tableName 
				, ISNULL(tableType,'') AS tableType 
				, ISNULL(CONVERT(VARCHAR,row_count),'') AS row_count 
				, ISNULL(CONVERT(VARCHAR,TotalSpaceMB),'') AS TotalSpaceMB 
				, ISNULL(CONVERT(VARCHAR,DataSpaceMB),'') AS DataSpaceMB 
				, ISNULL(CONVERT(VARCHAR,IndexSpaceMB),'') AS IndexSpaceMB 
				, ISNULL(CONVERT(VARCHAR,UnusedSpaceMB),'') AS UnusedSpaceMB 
				, ISNULL(CONVERT(VARCHAR,IN_ROW_DATA_MB), '') AS IN_ROW_DATA_MB 
				, ISNULL(CONVERT(VARCHAR,LOB_DATA_MB), '') AS LOB_DATA_MB 
				, ISNULL(CONVERT(VARCHAR,ROW_OVERFLOW_DATA_MB), '') AS ROW_OVERFLOW_DATA_MB 
				, ISNULL(CONVERT(VARCHAR,LastUserRead, 113), '') AS LastUserRead 
				, ISNULL(CONVERT(VARCHAR,LastUserUpdate, 113), '') AS LastUserUpdate 
				, ISNULL(CONVERT(VARCHAR,UserReads), '') AS UserReads
				, ISNULL(CONVERT(VARCHAR,UserUpdates), '') AS UserUpdates
				, ISNULL(TableTriggers,'') AS TableTriggers 
				, ISNULL(columnName,'') AS columnName 
				, ISNULL(DataType,'') AS DataType 
				, ISNULL(Size,'') AS Size 
				, ISNULL(IsIdentity,'') AS IsIdentity 
				, ISNULL(Mandatory,'') AS Mandatory 
				, ISNULL(DefaultValue,'') AS DefaultValue 
				, ISNULL(PrimaryKey,'') AS PrimaryKey 
				, ISNULL(IsComputed,'') AS IsComputed 
				, ISNULL(Collation,'') AS Collation 
				, ISNULL([definition],'') AS [Definition] 
				, ISNULL(ForeignKey,'') AS ForeignKey 
				, ISNULL(ReferencedColumn,'') AS ReferencedColumn 
				, ISNULL(Filestream,'') AS Filestream			 
				, ISNULL(TableDescription,'') AS TableDescription 
				, ISNULL(ColDescription,'') AS ColDescription 
			FROM cte 
			ORDER BY databaseName 
				, schemaName 
				, tableName 
				, Column_id 
	
END 

	
GO