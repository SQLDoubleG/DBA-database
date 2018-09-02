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
-- Create date: 24/02/2017
-- Description:	Returns information about Full text catalogs and index population.
--
-- Parameters:
--				@dbname
--
-- Log History:	
--				24/02/2017 RAG - Created
-- =============================================
CREATE PROCEDURE [dbo].[DBA_FTmonitoring]
	@dbname	SYSNAME = NULL
AS 
BEGIN

IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t

CREATE TABLE #t(
	database_name			SYSNAME			NOT NULL
	, FullTextCatalogName	SYSNAME			NOT NULL
	, object_id				INT				NOT NULL
	, index_name			SYSNAME			NOT NULL
	, total_row_count		INT				NULL
	, crawl_start_date		DATETIME		NULL
	, crawl_end_date		DATETIME		NULL
	, Status				NVARCHAR(60)	NULL
	, LastPopulationDate	DATETIME		NULL
	, n_fragments			INT				NULL
	, stdev_row_count		INT				NULL
	, max_row_count			INT				NULL
	, min_row_count			INT				NULL
)

INSERT INTO #t
EXECUTE sys.sp_MSforeachdb @command1 = N'

USE [?]

SELECT DB_NAME() AS database_name
		, c.Name AS FullTextCatalogName
		, i.object_id
		, OBJECT_NAME(i.object_id) AS index_name
		, SUM(f.row_count) AS [total_row_count]
		, i.crawl_start_date
		, i.crawl_end_date
		, CASE FULLTEXTCATALOGPROPERTY(c.Name, ''PopulateStatus'')
				WHEN 0 THEN ''Idle''
				WHEN 1 THEN ''Full population in progress''
				WHEN 2 THEN ''Paused''
				WHEN 3 THEN ''Throttled''
				WHEN 4 THEN ''Recovering''
				WHEN 5 THEN ''Shutdown''
				WHEN 6 THEN ''Incremental population in progress''
				WHEN 7 THEN ''Building index''
				WHEN 8 THEN ''Disk is full. Paused.''
				WHEN 9 THEN ''Change tracking''
			END AS Status
		, DATEADD(ss,FULLTEXTCATALOGPROPERTY(c.Name, ''PopulateCompletionAge''),''1/1/1990'') AS LastPopulationDate
		, COUNT(*) [n_fragments]
		, CONVERT(INT, STDEV(f.row_count)) AS [stdev_row_count]
		, MAX(f.row_count) [max_row_count]
		, MIN(f.row_count) [min_row_count]
-- SELECT row_count, *
	FROM sys.fulltext_catalogs c
		INNER JOIN sys.fulltext_indexes i
			ON i.fulltext_catalog_id = c.fulltext_catalog_id
		INNER JOIN sys.fulltext_index_fragments f
			ON f.table_id = i.object_id 
	GROUP BY c.Name, i.object_id, i.crawl_start_date, i.crawl_end_date

'

SELECT * FROM #t
	WHERE database_name = ISNULL(@dbname, database_name)

END
GO
