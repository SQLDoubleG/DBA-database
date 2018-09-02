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
-- Create date: May 2013
-- Description:	Return a list of instances for a given server
--				with useful information
-- =============================================
CREATE PROCEDURE [dbo].[repServerInstances]
	@serverName		SYSNAME = NULL
	, @OnlyCurrent	BIT		= 1
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @LastDataCollectionDate DATETIME

	SELECT @LastDataCollectionDate = DATEADD(DAY, -1, MAX([DataCollectionTime])) FROM dbo.ServerConfigurations AS I

	SELECT [InstanceName]
			, CASE WHEN I.DataCollectionTime > @LastDataCollectionDate THEN 'Yes' ELSE 'No' END AS IsCurrent
			, CASE WHEN s.isProduction = 1 THEN 'Yes' ELSE 'No' END AS IsProduction			
			, '' AS [DescriptiveVersion]
			, [Edition]
			, CONVERT(VARCHAR(128), P.[ProductLevel]) + ' (' + CONVERT(VARCHAR(128), P.[ProductVersion])  + ')' AS [ProductVersion]
			--, CASE 
			--	WHEN CONVERT(SMALLINT, RIGHT (P.[ProductVersion], CHARINDEX( '.', REVERSE(P.[ProductVersion]) ) - 1 )) 
			--		< CONVERT(SMALLINT,RIGHT (V.[ProductVersion], CHARINDEX( '.', REVERSE(V.[ProductVersion]) ) - 1 ) ) THEN 'No. Lastest ' +  V.[ProductLevel] + ' (' + V.[ProductVersion]  + ')'
			--	WHEN CONVERT(SMALLINT, RIGHT (P.[ProductVersion], CHARINDEX( '.', REVERSE(P.[ProductVersion]) ) - 1 )) 
			--		> CONVERT(SMALLINT,RIGHT (V.[ProductVersion], CHARINDEX( '.', REVERSE(V.[ProductVersion]) ) - 1 ) ) THEN 'Yes plus hotfix.' +  ' (' + V.[ProductLevel] + '-' + V.[ProductVersion]  + ')'
			--	ELSE 'Yes' END AS UpdatedToLatestSP
			, '' AS UpdatedToLatestSP
			--, CASE WHEN I.[ProductVersion] = V.[ProductVersion] THEN 'Yes' ELSE 'No. Lastest ' +  V.[ProductLevel] + ' (' + V.[ProductVersion]  + ')' END AS UpdatedToLatest
			--, V.[ProductLevel] AS LatestProductLevel
			--, V.[ProductVersion] AS LatestProductVersion
			, P.[Collation]
			, [max server memory (MB)] AS [Max Memory (MB)]
			, CONVERT(INT, [max server memory (MB)]) / 1024 AS MaxMemGB  
			, [min server memory (MB)] AS [Min Memory (MB)]
			, CONVERT(INT, [min server memory (MB)]) / 1024 AS MinMemGB  
			, [max degree of parallelism] AS [MaxDOP]
			, [Cost Threshold for Parallelism]
			, [cross db ownership chaining] AS [Cross-DB Ownership Chaining]
			, [optimize for ad hoc workloads]
			, [xp_cmdshell]
			, [Ad Hoc Distributed Queries]
			, I.[DataCollectionTime] AS [LastDataCollectionTime]
		FROM dbo.ServerConfigurations AS I
			INNER JOIN dbo.ServerProperties AS P
				ON P.server_name = I.server_name
			--LEFT JOIN dbo.CurrentSQLServerProductVersions AS V
			--	ON V.SQLServerProduct = P.DescriptiveVersion
			INNER JOIN dbo.ServerList AS s
				ON s.server_name = i.server_name
		WHERE I.[server_name] LIKE ISNULL(@serverName, I.[server_name])
			AND ( @OnlyCurrent = 0 OR I.DataCollectionTime > @LastDataCollectionDate )
		ORDER BY IsCurrent ASC
			, IsProduction ASC
			, I.[server_name]
END




GO
