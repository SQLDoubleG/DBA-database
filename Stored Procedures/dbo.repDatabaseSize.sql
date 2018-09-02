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
-- Create date: 14/09/2016
-- Description:	Return database growth
--
-- Change Log:
--				22/11/2017	RAG	Added the latest info when querying for partitions month or year.
--								Changed CTE to temp table for performance
--
-- =============================================
CREATE PROCEDURE [dbo].[repDatabaseSize] 
	@servername			SYSNAME		= NULL
	, @dbname			SYSNAME		= NULL
	, @dateFrom			DATE		= '20000101'
	, @dateTo			DATE		= '20501231'
	, @partition		VARCHAR(5)	= 'day' -- 'month' 'year'
	, @includeDeleted	BIT			= 0
AS
BEGIN
	
SET NOCOUNT ON

SET @dateFrom	= ISNULL(@dateFrom,		'20000101')
SET @dateTo		= ISNULL(@dateTo,		'20501231')
SET @partition	= ISNULL(@partition,	'day'	  )

IF @partition NOT IN ('day','month','year') BEGIN 
	RAISERROR ('The value passed to parameter @partition is not valid, please use ''day'',''month'' or ''year''', 16, 0, 0)
END

IF OBJECT_ID('tempdb..#db_size') IS NOT NULL DROP TABLE #db_size
	
SELECT CONCAT(YEAR(d.DataCollectionTime), '/', RIGHT('00' + CONVERT(VARCHAR, MONTH(d.DataCollectionTime)), 2)) AS MonthYear
		, ROW_NUMBER() OVER(PARTITION BY d.server_name, d.name ORDER BY d.DataCollectionTime ASC) AS RowNumber
		, ROW_NUMBER() OVER(PARTITION BY d.server_name, d.name, YEAR(d.DataCollectionTime) ORDER BY d.DataCollectionTime ASC) AS RowNumYear
		, ROW_NUMBER() OVER(PARTITION BY d.server_name, d.name, YEAR(d.DataCollectionTime), MONTH(d.DataCollectionTime) ORDER BY d.DataCollectionTime ASC) AS RowNumMonth
		,d.[DataCollectionTime]
		,d.[server_name]
		,d.[name]
		,d.[Size_GB]
		,d.[SpaceAvailable_GB]
		,d.[DataSpace_GB] 
		,d.[IndexSpace_GB]
		,d.[LogSpace_GB]
	INTO #db_size
	FROM [DBA].[dbo].[DatabaseSizeInformation] AS d
		LEFT JOIN DBA.dbo.DatabaseInformation AS c
			ON c.server_name = d.server_name
				AND c.name = d.name
	WHERE d.server_name = ISNULL(@servername, d.server_name)
		AND d.name = ISNULL(@dbname, d.name)
		AND d.DataCollectionTime BETWEEN @dateFrom AND @dateTo
		AND d.[Size_GB] IS NOT NULL
		AND (c.ID IS NOT NULL OR @includeDeleted = 1)

SELECT	CONVERT(VARCHAR, db.[DataCollectionTime], 103) AS DataCollectionDate
		, db.[DataCollectionTime]
		, db.[server_name]
		, db.[name]
		, db.[Size_GB]
		, db.[Size_GB]			- LAG([Size_GB],1,0)			OVER (PARTITION BY db.name ORDER BY db.name, db.MonthYear) AS [Size_GB_Growth]
		, db.[SpaceAvailable_GB]- LAG([SpaceAvailable_GB],1,0)	OVER (PARTITION BY db.name ORDER BY db.name, db.MonthYear) AS [SpaceAvailable_GB_Growth]
		, db.[DataSpace_GB]		- LAG([DataSpace_GB],1,0)		OVER (PARTITION BY db.name ORDER BY db.name, db.MonthYear) AS [DataSpace_GB_Growth]
		, db.[IndexSpace_GB]	- LAG([IndexSpace_GB],1,0)		OVER (PARTITION BY db.name ORDER BY db.name, db.MonthYear) AS [IndexSpace_GB_Growth]
		, db.[LogSpace_GB]		- LAG([LogSpace_GB],1,0)		OVER (PARTITION BY db.name ORDER BY db.name, db.MonthYear) AS [LogSpace_GB_Growth]
FROM #db_size AS db
		CROSS APPLY ( SELECT TOP 1 db2.server_name, db2.name, db2.RowNumber
						FROM #db_size AS db2 
						WHERE db2.server_name = db.server_name 
							AND db2.name = db.name
						ORDER BY db2.RowNumber DESC ) AS db2
	WHERE (@partition = 'day')
		OR  (@partition = 'month'	AND db.RowNumMonth = 1 )
		OR  (@partition = 'year'	AND db.RowNumYear = 1 )
		OR ( (@partition IN ('month', 'year') AND db.RowNumber = db2.RowNumber ) )
ORDER BY server_name, name, [DataCollectionTime]

IF OBJECT_ID('tempdb..#db_size') IS NOT NULL DROP TABLE #db_size

END
GO
