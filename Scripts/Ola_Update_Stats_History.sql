SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2021 Raul Gonzalez, @SQLDoubleG (RAG).
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
-- Create date: 18/06/2021
-- Description:	Reads the commandlog table to find Update Stats commands
--
-- Assupmtions:	The table commandlog exists in [master]
--
-- Log History:	
--				18/06/2021	Created
--
-- =============================================
USE [master];

DECLARE @dbname		SYSNAME = NULL;
DECLARE @tableName	SYSNAME	= NULL;

SELECT [ID]
		, [DatabaseName]
		, [SchemaName]
		, [ObjectName]
		, [ObjectType]
		, [StatisticsName]
		, [ExtendedInfo].value('(/ExtendedInfo/RowCount)[1]', 'BIGINT') AS [RowCount] 
		, [ExtendedInfo].value('(/ExtendedInfo/ModificationCounter)[1]', 'BIGINT') AS [ModificationCounter]        
		, CONVERT(decimal(15,2),
				([ExtendedInfo].value('(/ExtendedInfo/ModificationCounter)[1]', 'BIGINT') * 100.) 
					/ [ExtendedInfo].value('(/ExtendedInfo/RowCount)[1]', 'BIGINT')) AS [ModificationPercentage] 
		, [Command]
		, [CommandType]
		, [StartTime]
		, [EndTime]

        , ISNULL(NULLIF (CONVERT(VARCHAR(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 3600 / 24 ),'0') + '.', '') + 
			RIGHT('00' + CONVERT(VARCHAR(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 3600 % 24 ), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), DATEDIFF(SECOND, [StartTime], [EndTime]) / 60 % 60), 2) + ':' + 
			RIGHT('00' + CONVERT(VARCHAR(24), DATEDIFF(SECOND, [StartTime], [EndTime]) % 60), 2) AS [Duration]
		, [ErrorNumber]
		, [ErrorMessage]
    FROM dbo.CommandLog AS c
    WHERE CommandType = 'UPDATE_STATISTICS'
        AND [ObjectName] = ISNULL(@tableName, [ObjectName])
        AND DatabaseName = ISNULL(@dbname, DatabaseName)
    ORDER BY ID ASC;
