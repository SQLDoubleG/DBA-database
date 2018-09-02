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
--=============================================
-- Author:		Raul Gonzalez
-- Date:		02/10/2015
-- Description:	Returns the list of statements required to do a failover within a given availability group
--				The result must be executed on SQLCMD mode
--				This SP must be executed on the PRIMARY replica (to be sure of that, connect to the AG listener)
--
-- Log Changes:	
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_AG_failover]
	@AG	SYSNAME = NULL
AS

IF NOT EXISTS (SELECT 1 
					FROM sys.availability_replicas AS r
						LEFT JOIN sys.dm_hadr_availability_replica_states AS s
							ON s.replica_id = r.replica_id
								AND s.group_id = r.group_id
						INNER JOIN sys.availability_groups AS g
							ON g.group_id = s.group_id
					WHERE s.role_desc = 'PRIMARY') BEGIN 
	RAISERROR ('Please Connect to the PRIMARY replica to execute this procedure, if you don''t know which one it is, just connect to the listner.', 16, 0, 0)
	RETURN -100
END 

;WITH cte AS(
SELECT 1 AS sort_order
		, '--- YOU MUST EXECUTE THE FOLLOWING SCRIPT IN SQLCMD MODE.' AS SQL_STATEMENT
UNION
SELECT	CASE WHEN s.role_desc = 'SECONDARY' THEN 2 ELSE 3 END
		, 
		':Connect ' + replica_server_name + CHAR(10) +
			CASE WHEN s.role_desc = 'SECONDARY' THEN 'ALTER AVAILABILITY GROUP ' + QUOTENAME(g.name) + ' FORCE_FAILOVER_ALLOW_DATA_LOSS' + CHAR(10) + 'GO'
				WHEN s.role_desc = 'PRIMARY' THEN (SELECT 'ALTER DATABASE ' + QUOTENAME(database_name) + ' SET HADR RESUME' + CHAR(10) + 'GO' + CHAR(10) FROM sys.availability_databases_cluster FOR XML PATH(''))
			END 
--	SELECT *
	FROM sys.availability_replicas AS r
		LEFT JOIN sys.dm_hadr_availability_replica_states AS s
			ON s.replica_id = r.replica_id
				AND s.group_id = r.group_id
		INNER JOIN sys.availability_groups AS g
			ON g.group_id = s.group_id
	WHERE g.name = @AG
)

SELECT SQL_STATEMENT FROM cte ORDER BY sort_order
GO
