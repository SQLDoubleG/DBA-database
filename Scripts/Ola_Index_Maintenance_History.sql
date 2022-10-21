SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
--=============================================
-- Copyright (C) 2019 @SQLDoubleG
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
-- Author:		Raul Gonzalez, @SQLDoubleG (RAG)
-- Create date: 26/06/2019
-- Description:	Reads the commandlog table to find index maintenance commands
--
-- Log History:	
--				26/06/2019 RAG	Created
--
-- =============================================
USE [master];

DECLARE @dbname sysname = NULL;
DECLARE @tableName sysname = NULL;
DECLARE @indexName sysname = NULL;

SELECT [ID],
	   [DatabaseName],
	   [SchemaName],
	   [ObjectName],
	   [ObjectType],
	   [IndexName],
	   [IndexType],
	   [PartitionNumber],
	   [ExtendedInfo].value('(/ExtendedInfo/PageCount)[1]', 'bigint') * 8. / 1024 AS size_MB,
	   [ExtendedInfo].value('(/ExtendedInfo/Fragmentation)[1]', 'decimal(8,5)') AS fragmentation,
	   [CommandType] + CASE WHEN Command LIKE '%REBUILD%' THEN '_REBUILD' ELSE '_REORGANIZE' END AS [CommandType],
	   [Command],
	   [StartTime],
	   [EndTime],
	   ISNULL(NULLIF(CONVERT(varchar(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 3600 / 24), '0') + '.', '')
		   + RIGHT('00' + CONVERT(varchar(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 3600 % 24), 2) + ':'
		   + RIGHT('00' + CONVERT(varchar(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 60 % 60), 2) + ':'
		   + RIGHT('00' + CONVERT(varchar(24), DATEDIFF(SECOND, [StartTime], [EndTime]) % 60), 2) AS duration,
	   [ErrorNumber],
	   [ErrorMessage]
FROM dbo.CommandLog
WHERE CommandType = 'ALTER_INDEX'
	AND [ObjectName] = ISNULL(@tableName, [ObjectName])
	AND IndexName = ISNULL(@indexName, IndexName)
	AND DatabaseName = ISNULL(@dbname, DatabaseName)
ORDER BY ID ASC;