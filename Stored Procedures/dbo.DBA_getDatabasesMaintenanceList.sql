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
-- Create date: 17/02/2015
-- Description:	Returns list of databases for maintenance
--				It will be excluded from this list if the database
--					- Is not ONLINE
--					- Is READ_ONLY
--					- Is a snapshot
--					- Is SINGLE_USER
--					- Is a non readable replica (only for SQL 2012 onwards)
--
-- Log History:	
--				04/11/2016 - SZO - Added clause to exclude '%checkDB' databases as they are getting picked up around 03:30,
--									but getting dropped before they get selected from the cursor.
--				04/01/2018 - RAG - Added columns to allow secondary replica databases to run backups and checkdb
--									- role TINYINT
--									- secondary_role_allow_connections TINYINT
-- 
-- Examples:
--				EXECUTE [dbo].[DBA_getDatabasesMaintenanceList]
-- =============================================
CREATE PROCEDURE [dbo].[DBA_getDatabasesMaintenanceList]
AS
BEGIN

	IF OBJECT_ID('tempdb..#t') IS NOT NULL DROP TABLE #t

	CREATE TABLE #t (database_id INT NOT NULL, name SYSNAME NOT NULL, role TINYINT NOT NULL, secondary_role_allow_connections TINYINT NOT NULL)
	INSERT INTO #t ( database_id, name, role, secondary_role_allow_connections)
		SELECT db.database_id, db.[name], 1, 0
			FROM sys.databases AS db
			WHERE db.state = 0 -- Online databases only
				AND db.is_read_only = 0 -- exclude read_only databases
				AND db.source_database_id IS NULL -- exclude snapshots
				AND db.user_access = 0 -- exclude single user databases
				AND db.name NOT IN ('model', 'tempdb')
				AND db.[name] NOT LIKE '%checkDB';

	-- Delete if it's a secondary replica
	IF ([dbo].[getNumericSQLVersion](NULL)) >= 11 BEGIN
		EXECUTE sp_executesql @stmt = N'
			UPDATE t
				SET t.role = s.role
					, t.secondary_role_allow_connections = r.secondary_role_allow_connections
				FROM #t AS t
					INNER JOIN sys.databases AS db 
						ON db.database_id = t.database_id
					INNER JOIN sys.dm_hadr_availability_replica_states AS s
						ON s.replica_id = db.replica_id
					INNER JOIN sys.availability_replicas AS r
						ON r.replica_id = s.replica_id'
	END
	SELECT database_id ,
           name ,
           role ,
           secondary_role_allow_connections
		FROM #t 
END

GO
