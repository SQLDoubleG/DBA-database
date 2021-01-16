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
-- Author:      Raul Gonzalez
-- Create date:	19/08/2013
-- Description: Returns all database users with database roles and permissions at object level
--					for the given database or all databases if not specified
--
-- Change Log:	20/09/2013 RAG - Modified the query to display permissions assigned to User defined database roles
--				26/09/2013 RAG - Added parameter @includeSystemDBs to include or not System Databases 
--				21/01/2014 RAG - Added recordset with all database users with their roles
--				25/03/2014 RAG - Added fuctionality to include permissions for user defined database roles 
--				                                   and to detect orphan users (without a login)
--				29/02/2016 RAG - Added check for User schema to exist in order to generate a DROP SCHEMA statement
--				15/03/2016 SZO - Added column granularity to REVOKE statements
--				16/03/2016 SZO - Added column granularity to [permission_list] column
--				24/01/2018 RAG - Added column [included_users] which will display all users that are member of a database role
--									Removed condition to exclude system database roles
--				12/03/2020 RAG - Added column [CREATE_DB_ROLE] 
--				11/08/2020 RAG - Added parameter @onlyOrphanUsers to identify orphan users
--				16/01/2021 RAG - Added parameter @EngineEdition
--									Removed dependencies and solve collation issues to run on Azure SQL DB
--									Display 'CONTAINED USER' if that is the case
--
-- Params are concatenated to the @sqlstring string to avoid problems in databases with different collation than [DBA]
--
-- =============================================

DECLARE	@dbname					sysname --= 'msdb'
		, @db_principal_name	sysname = NULL
		, @srv_principal_name 	sysname = NULL
		, @onlyOrphanUsers		BIT		= 1
		, @includeSystemDBs		BIT		= 1
		, @EngineEdition		INT		= CONVERT(INT, SERVERPROPERTY('EngineEdition'))

IF @EngineEdition = 5 BEGIN
-- Azure SQL Database, the script can't run on multiple databases
	SET @dbname	= DB_NAME()
END

SET NOCOUNT ON;

DECLARE @countDBs INT = 1, @numDBs INT, @sqlstring NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#databases')			IS NOT NULL DROP TABLE #databases;
IF OBJECT_ID('tempdb..#all_db_users')		IS NOT NULL DROP TABLE #all_db_users;
IF OBJECT_ID('tempdb..#all_db_permissions') IS NOT NULL DROP TABLE #all_db_permissions;

CREATE TABLE #all_db_users (
	database_id				INT
	, principal_id			INT
	, principal_sid			VARBINARY(85)
	, principal_name		sysname
	, principal_type_desc	NVARCHAR(60)
	, default_schema_name	sysname		  NULL
	, has_db_access			BIT
	, authentication_type	SYSNAME
	, database_roles		NVARCHAR(512) NULL
	, included_users		NVARCHAR(4000) NULL
	, DROP_USER_SCHEMA		NVARCHAR(256)
	, CREATE_DB_ROLE		NVARCHAR(4000)
	, DROP_DB_ROLE			NVARCHAR(4000)
	, DROP_DB_USER			NVARCHAR(256)
);

CREATE TABLE #all_db_permissions (
	database_id				INT
	, principal_sid			VARBINARY(85)
	, principal_name		sysname
	, principal_type_desc	sysname
	, class_desc			sysname		NULL
	, object_name			sysname		NULL
	, permission_list		NVARCHAR(512) NULL
	, permission_state_desc sysname
	, REVOKE_PERMISSION		NVARCHAR(4000)
);

IF @dbname IS NOT NULL BEGIN
	SET @includeSystemDBs = 1;
END;

SELECT IDENTITY(INT, 1, 1) AS ID, name
INTO #databases
	FROM sys.databases
	WHERE state					 = 0
			AND name LIKE ISNULL (@dbname, name)
			AND (@includeSystemDBs = 1 OR database_id > 4);

SET @numDBs = @@ROWCOUNT;

WHILE @countDBs <= @numDBs BEGIN

	SET @dbname = (SELECT name FROM #databases WHERE ID = @countDBs);
	SET @sqlstring	= CASE WHEN @EngineEdition <> 5 THEN N'USE ' + QUOTENAME(@dbname) ELSE '' END
			+ N'
            DECLARE @db_principal_name SYSNAME = '
				+ ISNULL ((N'''' + @db_principal_name + N''''), N'NULL')
				+ CONVERT (
						NVARCHAR(MAX)
					, N'
            
			DECLARE @numericVersion INT = CONVERT(INT, PARSENAME(CONVERT(SYSNAME, SERVERPROPERTY(''ProductVersion'')),4))

            -- All database users and the list of database roles
            INSERT INTO #all_db_users (
                    database_id
                    , principal_id
                    , principal_sid
                    , principal_name
					, principal_type_desc
                    , default_schema_name
                    , has_db_access
					, authentication_type
                    , database_roles
					, included_users
                    , DROP_USER_SCHEMA
                    , CREATE_DB_ROLE
                    , DROP_DB_ROLE
                    , DROP_DB_USER
            )
                SELECT DB_ID() AS database_id
						, dbp.principal_id AS principal_id
						, dbp.sid AS principal_sid
						, dbp.name AS principal_name
						, dbp.type_desc AS principal_type_desc
						, dbp.default_schema_name
						, CASE 
									WHEN dp.state IN (''G'', ''W'') THEN 1 
									ELSE 0 
								END AS [has_db_access]
						, authentication_type_desc
						, STUFF((SELECT '', '' + dbr.name 
									FROM sys.database_principals dbr 
											LEFT JOIN sys.database_role_members AS drm
													ON drm.member_principal_id = dbp.principal_id
									WHERE dbr.principal_id = drm.role_principal_id
									FOR XML PATH('''')),1,2,'''') AS database_roles

						, STUFF((SELECT '', '' + USER_NAME(dbr.member_principal_id)
									FROM sys.database_role_members AS dbr
									WHERE dbr.role_principal_id = dbp.principal_id
									FOR XML PATH('''')),1,2,'''') AS included_users

						, CASE WHEN dbp.default_schema_name = dbp.name AND EXISTS (SELECT * FROM sys.schemas WHERE name = dbp.default_schema_name) THEN 
									''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) + ''DROP SCHEMA '' + QUOTENAME(dbp.default_schema_name) + CHAR(10) +  ''GO'' + CHAR(10) +
									''ALTER USER '' + QUOTENAME(dbp.name) + '' WITH DEFAULT_SCHEMA = [dbo]'' + CHAR(10) + ''GO'' 
									ELSE '''' 
								END AS DROP_USER_SCHEMA
						, (SELECT ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) +
							''CREATE ROLE '' + QUOTENAME(dbr.name) + CHAR(10) + 
											CASE WHEN @numericVersion >= 11 
													THEN ''ALTER ROLE '' +  QUOTENAME(dbr.name) + '' ADD MEMBER '' + QUOTENAME(dbp.name)
													ELSE '' EXECUTE sp_droprolemember '' + QUOTENAME(dbr.name) + '', '' + QUOTENAME(dbp.name) 
											END + CHAR(10) + ''GO'' + CHAR(10) 
									FROM sys.database_principals dbr 
									LEFT JOIN sys.database_role_members AS drm
											ON drm.member_principal_id = dbp.principal_id
									WHERE dbr.principal_id = drm.role_principal_id
									FOR XML PATH('''')) AS CREATE_DB_ROLE
						, (SELECT ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) +
											CASE WHEN @numericVersion >= 11 
													THEN ''ALTER ROLE '' +  QUOTENAME(dbr.name) + '' DROP MEMBER '' + QUOTENAME(dbp.name)
													ELSE '' EXECUTE sp_droprolemember '' + QUOTENAME(dbr.name) + '', '' + QUOTENAME(dbp.name) 
											END + CHAR(10) + ''GO'' + CHAR(10) 
									FROM sys.database_principals dbr 
									LEFT JOIN sys.database_role_members AS drm
											ON drm.member_principal_id = dbp.principal_id
									WHERE dbr.principal_id = drm.role_principal_id
									FOR XML PATH('''')) AS DROP_DB_ROLE
						, ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) + ''DROP USER '' + QUOTENAME(dbp.name) + CHAR(10) + ''GO''  AS DROP_DB_USER
                        FROM sys.database_principals AS dbp 
                                LEFT JOIN sys.database_permissions AS dp 
                                        ON dp.grantee_principal_id = dbp.principal_id 
                                            AND dp.type = ''CO''
                        WHERE ( dbp.type IN (''U'', ''S'', ''G'', ''C'', ''K'') -- S = SQL user, U = Windows user, G = Windows group, C = User mapped to a certificate, K = User mapped to an asymmetric key
                                        AND dbp.name LIKE ISNULL(@db_principal_name, dbp.name) )
                        -- To get database roles 
                                OR ( dbp.type IN (''R'')
                                        AND dbp.name LIKE ISNULL(@db_principal_name, dbp.name)
                                        -- AND dbp.principal_id < 16384 
										) -- db_owner
              
                    -- get a line per database user / object / permission state
                    ;WITH users_with_permission AS (
                        SELECT DISTINCT 
                                        p.grantee_principal_id
                                        , p.class
                                        , CASE WHEN p.class = 1 THEN o.type_desc ELSE p.class_desc END AS class_desc
                                        , p.major_id               
                                        , p.state
                                        , p.state_desc
                                        , dbp.principal_sid
                                        , dbp.principal_name
                                        , dbp.principal_type_desc
                                FROM sys.database_permissions AS p
                                        INNER JOIN #all_db_users AS dbp
                                            ON p.grantee_principal_id = dbp.principal_id
                                        LEFT JOIN sys.objects AS o
                                            ON o.object_id = p.major_id
                                WHERE dbp.database_id = DB_ID()
                    )
                    INSERT INTO #all_db_permissions (
                        database_id
                        , principal_sid
                        , principal_name
                        , principal_type_desc
                        , class_desc
                        , object_name
                        , permission_list
                        , permission_state_desc
                        , REVOKE_PERMISSION
                    )
				SELECT 
					DB_ID() AS [database_id]
					, p.principal_sid
					, p.principal_name
					, p.principal_type_desc
					, p.class_desc
					,	CASE
							WHEN p.class = 0 THEN QUOTENAME(DB_NAME())
							WHEN p.class = 1 THEN QUOTENAME(OBJECT_SCHEMA_NAME(p.major_id)) + ''.'' + QUOTENAME(OBJECT_NAME(p.major_id))
							WHEN p.class = 3 THEN QUOTENAME(sch.name)
							WHEN p.class = 6 THEN QUOTENAME(tt.name)
						END AS [object_name]
					,	STUFF(
							(SELECT 
								'', '' + per.[permission_name]
								FROM (
									--==== Because column updates create multiple ''UPDATE'' entries in the sys.database_permissions table,
										-- there is a need to select distinct or group this table to remove them and only get a single row. 
									SELECT 
									DISTINCT 
											grantee_principal_id
											, major_id
											,	CASE 
													WHEN minor_id > 0 THEN [permission_name] + 
													--==== Add the columns that the permission is granted on
														-- specified to the [permission_list] columns
														+ '' ('' 
														+ STUFF(
															(SELECT 
																'', '' + c.name 
																FROM sys.columns AS [c] 
																	LEFT OUTER JOIN sys.database_permissions AS [col_dp]
																		ON c.[object_id] = col_dp.major_id
																			AND c.column_id = col_dp.minor_id
																WHERE col_dp.grantee_principal_id = db_per.grantee_principal_id
																	AND col_dp.major_id = db_per.major_id
																	AND col_dp.[type] = db_per.[type]
																FOR XML PATH('''')), 1, 1, '''') COLLATE DATABASE_DEFAULT
														+ '' )''
													ELSE [permission_name]
												END AS [permission_name]
											, class
											, [state]
										FROM sys.database_permissions as [db_per]) AS [per]

								WHERE per.grantee_principal_id = p.grantee_principal_id
								AND per.class = p.class
								AND per.major_id = p.major_id
								AND per.[state] = p.[state]
								ORDER BY per.[permission_name] ASC
								FOR XML PATH(''''))
							, 1, 2, '''') AS [permission_list]
					, p.state_desc
					,	STUFF(
							(SELECT 
								CHAR(10) + ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) 
								+ ''REVOKE '' + per.[permission_name] 
								+ ISNULL('' ON '' + (	CASE
														WHEN p.class = 0 THEN ''DATABASE::''	+ QUOTENAME(DB_NAME())												
														WHEN p.class = 1 THEN ''OBJECT::''		+ QUOTENAME(OBJECT_SCHEMA_NAME(p.major_id)) + ''.'' + QUOTENAME(OBJECT_NAME(p.major_id))
														WHEN p.class = 3 THEN ''SCHEMA::''		+ QUOTENAME(SCHEMA_NAME(p.major_id))
														WHEN p.class = 6  THEN ''TYPE::''		+ QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name)
														-- TODO: Add joins to get those names
														WHEN p.class = 5  THEN QUOTENAME(''Assembly'')
														WHEN p.class = 10 THEN QUOTENAME(''XML Schema Collection'')
														WHEN p.class = 15 THEN QUOTENAME(''Message Type'')
														WHEN p.class = 16 THEN QUOTENAME(''Service Contract'')
														WHEN p.class = 17 THEN QUOTENAME(''Service'')
														WHEN p.class = 18 THEN QUOTENAME(''Remote Service Binding'')
														WHEN p.class = 19 THEN QUOTENAME(''Route'')
														WHEN p.class = 23 THEN QUOTENAME(''Full-Text Catalog'')
														WHEN p.class = 24 THEN QUOTENAME(''Symmetric Key'')
														WHEN p.class = 25 THEN QUOTENAME(''Certificate'')
														WHEN p.class = 26 THEN QUOTENAME(''Asymmetric Key'')
														ELSE NULL
													END), '''')
								--==== Permissions on columns
								+ ISNULL('' ('' 
									+ STUFF(
										(SELECT 
											'', '' + c.name 
											FROM sys.columns AS [c] 
												LEFT OUTER JOIN sys.database_permissions AS [col_dp]
													ON c.[object_id] = col_dp.major_id
														AND c.column_id = col_dp.minor_id
											WHERE col_dp.grantee_principal_id = per.grantee_principal_id
												AND col_dp.major_id = per.major_id
												AND col_dp.[type] = per.[type]
											FOR XML PATH('''')), 1, 1, '''')
									+ '' )'', '''')
								+ '' TO '' + QUOTENAME(p.principal_name) + CHAR(10) + ''GO''
				
							FROM (
									--==== Because column updates create multiple ''UPDATE'' entries in the sys.database_permissions table,
										-- there is a need to select distinct or group this table to remove them and only get a single row. 
									SELECT 
									DISTINCT 
											grantee_principal_id
											, major_id
											, [permission_name]
											, class
											, [state]
											, [type]
										FROM sys.database_permissions) AS [per]
								LEFT JOIN sys.types AS t
									ON t.user_type_id = per.major_id
			
							WHERE per.grantee_principal_id = p.grantee_principal_id
							AND per.class = p.class
							AND per.major_id = p.major_id
							AND per.[state] = p.[state]
							ORDER BY per.[permission_name]
							FOR XML PATH(''''))
							, 1, 1, '''') AS [REVOKE_PERMISSION]

					FROM users_with_permission AS p
						LEFT JOIN sys.schemas AS sch
							ON sch.schema_id = p.major_id
								AND p.class = 3
						LEFT JOIN sys.table_types AS tt
							ON tt.user_type_id = p.major_id
						-- To do, add joins to display info for each class
		              
            ');

	--SELECT @sqlstring
	EXECUTE sp_executesql @sqlstring;

	SET @countDBs = @countDBs + 1;
END;

SELECT DB_NAME (dbp.database_id)							 AS database_name
	, dbp.principal_name
	, dbp.principal_type_desc
	, dbp.default_schema_name
	, CASE WHEN dbp.has_db_access = 1 THEN 'Yes' ELSE 'No' END AS has_db_access
	, CASE WHEN sp.name IS NULL AND dbp.authentication_type = 'DATABASE' THEN 'N/A' ELSE sp.name END	AS login_name
	, CASE WHEN sp.type_desc IS NULL AND dbp.authentication_type = 'DATABASE' THEN 'CONTAINED USER' ELSE sp.name END	AS login_type
	, dbp.database_roles
	, ISNULL(dbp.included_users, '') AS included_users
	, dbp.DROP_USER_SCHEMA
	, dbp.CREATE_DB_ROLE
	, dbp.DROP_DB_ROLE
	, dbp.DROP_DB_USER
	FROM #all_db_users					 AS dbp
			LEFT JOIN sys.server_principals AS sp
				ON sp.sid = dbp.principal_sid
	WHERE ISNULL (sp.name, '') LIKE COALESCE (@srv_principal_name, sp.name, '')
		AND (@onlyOrphanUsers = 0 OR
			(dbp.principal_type_desc = 'SQL_USER' 
				AND sp.name IS NULL 
				AND dbp.principal_name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys'))
			)
	ORDER BY database_name ASC, dbp.principal_name ASC;

SELECT DB_NAME (dbp.database_id) AS database_name
		, dbp.principal_name
		--, dbp.principal_type_desc
		--, sp.name					 AS login_name
		--, sp.type_desc			 login_type
		--, dbp.class_desc
		, dbp.object_name
		, dbp.permission_list
		, dbp.permission_state_desc
		, dbp.REVOKE_PERMISSION
	FROM #all_db_permissions			 AS dbp
			LEFT JOIN sys.server_principals AS sp
				ON sp.sid = dbp.principal_sid
	WHERE ISNULL (sp.name, '') LIKE COALESCE (@srv_principal_name, sp.name, '')
		AND (@onlyOrphanUsers = 0 OR
			(dbp.principal_type_desc = 'SQL_USER' 
				AND sp.name IS NULL 
				AND dbp.principal_name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys'))
			)
	ORDER BY database_name, dbp.principal_name, dbp.class_desc, dbp.object_name;

GO