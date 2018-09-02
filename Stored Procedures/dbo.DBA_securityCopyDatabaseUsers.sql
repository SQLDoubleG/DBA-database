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
-- Create date: 10/11/2015
-- Description:	Returns the code to clone one server/database principal (user or role) for the given database or all databases if not specified
--
-- Parameters:
--				@dbname					The script will run only for the database if provided
--				@server_principal_name	The new database users will be created for this login, user WITHOUT LOGIN will be used if not provided
--				@db_principal_name		Database principal to copy from, user or database role
--				@new_db_principal_name	New database principal
--				@syntaxSQLVersion		Numeric version for SQL Engine, versions < 11 will use [sp_addrolemember], otherwise ALTER ROLE will be used
--				@includeSystemDBs		To include or not system databases
--
-- Change Log:	10/11/2015 RAG - Created
--				16/03/2016 SZO - Added column permission level granularity
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_securityCopyDatabaseUsers]
	@dbname							SYSNAME			= NULL
	, @server_principal_name		SYSNAME			= NULL
	, @db_principal_name			SYSNAME			
	, @new_server_principal_name	SYSNAME			= NULL
	, @new_db_principal_name		SYSNAME			
	, @syntaxSQLVersion				DECIMAL(3,1)	= NULL
	, @includeSystemDBs				BIT				= 1

AS	
BEGIN

	SET NOCOUNT ON

	DECLARE @countDBs	INT = 1
			, @numDBs	INT
			, @sql		NVARCHAR(MAX) 

	IF OBJECT_ID('tempdb..#all_db_users')		IS NOT NULL	DROP TABLE #all_db_users
	IF OBJECT_ID('tempdb..#all_db_permissions') IS NOT NULL	DROP TABLE #all_db_permissions

	CREATE TABLE #all_db_users(
		database_id					INT
		, principal_sid				VARBINARY(85)
		, principal_name			SYSNAME
		, principal_type_desc		NVARCHAR(60)
		, default_schema_name		SYSNAME NULL
		, has_db_access				BIT
		, CREATE_NEW_PRINCIPAL	NVARCHAR(256)
		, CREATE_NEW_ROLES		NVARCHAR(1000)
	)

	CREATE TABLE #all_db_permissions ( 
		database_id					INT
		, principal_sid				VARBINARY(85)
		, SET_PERMISSIONS			NVARCHAR(MAX))

	IF @server_principal_name	IS NULL BEGIN RAISERROR ('Parameter @server_principal_name was not passed to the SP'	, 1, 1, 1) WITH NOWAIT	END
	IF @db_principal_name		IS NULL BEGIN RAISERROR ('Please provide a value for parameter @db_principal_name'		, 16, 1, 1) RETURN -200 END
	IF @new_db_principal_name	IS NULL BEGIN RAISERROR ('Please provide a value for parameter @new_db_principal_name'	, 16, 1, 1) RETURN -300 END
	
	IF @dbname IS NOT NULL BEGIN SET @includeSystemDBs = 1 END

	-- If not specified use current instance version
	IF @syntaxSQLVersion IS NULL BEGIN SET @syntaxSQLVersion = DBA.dbo.getNumericSQLVersion(NULL) END	
	
	-- Create the new login if provided and does not exist from the exisisting one
	INSERT INTO #all_db_users
	        ( database_id ,
	          principal_sid ,
	          principal_name ,
	          principal_type_desc ,
	          default_schema_name ,
	          has_db_access ,
	          CREATE_NEW_PRINCIPAL ,
	          CREATE_NEW_ROLES
	        )
	SELECT DB_ID('master')												AS database_id
			, sp.sid													AS principal_sid
			, sp.name													AS principal_name
			, sp.type_desc												AS principal_type_desc
			, ''														AS default_schema_name
			, CASE WHEN sp.is_disabled = 1 THEN 0 ELSE 1 END			AS has_db_access
			, 'USE [master]' + CHAR(10) + 
				'CREATE LOGIN ' + @new_server_principal_name + ' FROM WINDOWS' AS CREATE_NEW_PRINCIPAL
			, ISNULL(
				STUFF( (SELECT CHAR(10) + 
							CASE 
								WHEN 11 < 11 THEN 'EXECUTE sp_addsrvrolemember ' + @new_server_principal_name + ', ' + SUSER_NAME(srm.role_principal_id)
								WHEN 11 >= 11 THEN 'ALTER SERVER ROLE ' + SUSER_NAME(srm.role_principal_id) + ' ADD MEMBER ' + @new_server_principal_name
							END + CHAR(10) + 'GO'
						FROM sys.server_role_members AS srm 
						WHERE srm.member_principal_id = sp.principal_id 
						FOR XML PATH('')), 1, 1, ''), '')					AS CREATE_NEW_ROLES
		FROM sys.server_principals AS sp
		WHERE sp.name = @server_principal_name
			AND NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @new_server_principal_name)

	
	-- Get all databases or the one provided
	SELECT IDENTITY(INT, 1, 1) AS ID
			, name 
		INTO #databases
		FROM sys.databases 
		WHERE state = 0
			AND name LIKE ISNULL(@dbname, name)
			AND ( @includeSystemDBs = 1 OR database_id > 4 )

	SET @numDBs = @@ROWCOUNT

	WHILE @countDBs <= @numDBs BEGIN
	
		SET @dbname	= (SELECT name FROM #databases WHERE ID = @countDBs)
		SET @sql	= N'
		
		USE ' + QUOTENAME(@dbname) + CONVERT(NVARCHAR(MAX), N'

		-- All database users and the list of database roles
		INSERT INTO #all_db_users 
			SELECT DB_ID() AS database_id
					, dbp.sid AS principal_sid
					, dbp.name AS principal_name
					, dbp.type_desc AS principal_type_desc
					, dbp.default_schema_name
					, CASE 
							WHEN dp.state IN (''G'', ''W'') THEN 1 
							ELSE 0 
						END AS [has_db_access]

					, ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) + 
						
						CASE WHEN dbp.type = ''R'' THEN 
								''CREATE ROLE '' + QUOTENAME(@new_db_principal_name)
							ELSE 
						
								''CREATE USER '' + QUOTENAME(@new_db_principal_name) +
									CASE WHEN @server_principal_name COLLATE DATABASE_DEFAULT IS NOT NULL THEN '' FROM LOGIN '' + QUOTENAME(@new_server_principal_name) 
										ELSE '' WITHOUT LOGIN'' 
									END +
								'' WITH DEFAULT_SCHEMA = '' + QUOTENAME(dbp.default_schema_name) + CHAR(10) + ''GO''  
							END AS CREATE_NEW_PRINCIPAL

					, (SELECT ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) +
								CASE WHEN @syntaxSQLVersion >= 11 
									THEN ''ALTER ROLE '' +  QUOTENAME(USER_NAME(role_principal_id)) + '' ADD MEMBER '' + QUOTENAME(@new_db_principal_name)
									ELSE ''EXECUTE sp_addrolemember '' + QUOTENAME(USER_NAME(role_principal_id)) + '', '' + QUOTENAME(@new_db_principal_name) 
								END + CHAR(10) + ''GO'' + CHAR(10) 
							FROM sys.database_role_members AS drm
							WHERE dbp.principal_id = drm.member_principal_id
							FOR XML PATH('''')) AS CREATE_NEW_ROLES

				FROM sys.database_principals dbp 
					LEFT JOIN sys.database_permissions AS dp 
						ON dp.grantee_principal_id = dbp.principal_id 
							AND dp.type = ''CO'' 	-- Connect to database permission
				WHERE dbp.type IN (''U'', ''S'', ''G'', ''C'', ''K'', ''R'') -- S = SQL user, U = Windows user, G = Windows group, C = User mapped to a certificate, K = User mapped to an asymmetric key, R = database role
					AND dbp.name = @db_principal_name 

		
			-- get a line per database user / object / permission state
			INSERT INTO #all_db_permissions (
					database_id
					, principal_sid
					, SET_PERMISSIONS)

				SELECT DB_ID() AS [database_id]
					, USER_SID(db_per_02.grantee_principal_id) AS [principal_sid]
					, ''USE '' + QUOTENAME(DB_NAME()) + CHAR(10) + ''GO'' + CHAR(10) + state_desc + '' '' + permission_name + ISNULL('' ON '' + 
						( CASE 
								WHEN db_per_02.class = 0 THEN ''DATABASE::''	+ QUOTENAME(DB_NAME())												
								WHEN db_per_02.class = 1 THEN ''OBJECT::''	+ QUOTENAME(OBJECT_SCHEMA_NAME(db_per_02.major_id)) + ''.'' + QUOTENAME(OBJECT_NAME(db_per_02.major_id))
								WHEN db_per_02.class = 3 THEN ''SCHEMA::''	+ QUOTENAME(SCHEMA_NAME(db_per_02.major_id))
								WHEN db_per_02.class = 6  THEN ''TYPE::''		+ QUOTENAME(SCHEMA_NAME(tp.schema_id)) + ''.'' + QUOTENAME(TYPE_NAME(tp.user_type_id))
								-- Todo: get object names
								WHEN db_per_02.class = 5  THEN QUOTENAME(''Assembly'')
								WHEN db_per_02.class = 10 THEN QUOTENAME(''XML Schema Collection'')
								WHEN db_per_02.class = 15 THEN QUOTENAME(''Message Type'')
								WHEN db_per_02.class = 16 THEN QUOTENAME(''Service Contract'')
								WHEN db_per_02.class = 17 THEN QUOTENAME(''Service'')
								WHEN db_per_02.class = 18 THEN QUOTENAME(''Remote Service Binding'')
								WHEN db_per_02.class = 19 THEN QUOTENAME(''Route'')
								WHEN db_per_02.class = 23 THEN QUOTENAME(''Full-Text Catalog'')
								WHEN db_per_02.class = 24 THEN QUOTENAME(''Symmetric Key'')
								WHEN db_per_02.class = 25 THEN QUOTENAME(''Certificate'')
								WHEN db_per_02.class = 26 THEN QUOTENAME(''Asymmetric Key'')
								ELSE NULL 
							END ) , '''')
						--==== Add in column granularity, if applicable
						+ ISNULL('' ('' + 
							STUFF(
								(SELECT 
									'', '' + c_01.name 
									FROM sys.columns AS [c_01]
										LEFT OUTER JOIN sys.database_permissions AS [db_per_03]
										ON c_01.[object_id] = db_per_03.major_id
											AND c_01.column_id = db_per_03.minor_id
									WHERE db_per_03.grantee_principal_id = db_per_02.grantee_principal_id
									AND db_per_03.major_id = db_per_02.major_id
									AND db_per_03.[type] = db_per_02.[type]
									ORDER BY c_01.name ASC
									FOR XML PATH(''''))
									, 1, 1, '''')
									+ '' ) '', '''')
						+ '' TO '' + QUOTENAME(@new_db_principal_name) + CHAR(10) + ''GO'' AS [SET_PERMISSIONS]
					FROM (
						--==== Need to limit to one entry per object and permission
							-- as adding column level permissions creates
							-- multiple entries per object in the 
							-- sys.database_permissions table
						SELECT 
						DISTINCT
							db_per_01.grantee_principal_id
							, db_per_01.major_id
							, db_per_01.[type] 
							, db_per_01.[permission_name]
							, db_per_01.class
							, db_per_01.[state_desc]
							FROM sys.database_permissions AS [db_per_01]) AS [db_per_02]
								LEFT OUTER JOIN sys.table_types AS [tp]
									ON tp.user_type_id = db_per_02.major_id
							WHERE db_per_02.grantee_principal_id = USER_ID(@db_principal_name)


		')		
		EXECUTE sp_executesql @sql
				, @params = N'@syntaxSQLVersion	DECIMAL(3,1), @server_principal_name SYSNAME, @db_principal_name SYSNAME, @new_server_principal_name SYSNAME, @new_db_principal_name SYSNAME'
				, @syntaxSQLVersion				= @syntaxSQLVersion
				, @server_principal_name		= @server_principal_name	
				, @db_principal_name			= @db_principal_name		
				, @new_server_principal_name	= @new_server_principal_name	
				, @new_db_principal_name		= @new_db_principal_name	

		SET @countDBs = @countDBs + 1
	END

	SELECT DB_NAME(database_id)										AS database_name
			, ISNULL(principal_name		, '')						AS principal_name
			, ISNULL(principal_type_desc, '')						AS principal_type_desc
			, ISNULL(default_schema_name, '')						AS default_schema_name
			, CASE WHEN has_db_access = 1 THEN 'Yes' ELSE 'No' END	AS has_db_access
			, ISNULL(sp.name, '')									AS login_name
			, ISNULL(sp.type_desc, '')								AS login_type
			, ISNULL(CREATE_NEW_PRINCIPAL, '')						AS CREATE_NEW_PRINCIPAL
			, ISNULL(CREATE_NEW_ROLES, '')							AS CREATE_NEW_ROLES
			, ISNULL(
				(SELECT SET_PERMISSIONS + CHAR(10) AS [text()]
					FROM #all_db_permissions AS p 
					WHERE p.database_id = dbp.database_id
						AND p.principal_sid = dbp.principal_sid
					FOR XML PATH('')), '')							AS SET_PERMISSIONS
		FROM #all_db_users AS dbp
			LEFT JOIN sys.server_principals AS sp
				ON sp.sid = dbp.principal_sid
		ORDER BY CASE WHEN database_id = DB_ID('master') THEN 1 ELSE 2 END ASC
			, database_name ASC
			, principal_name ASC

	DROP TABLE #all_db_users
	DROP TABLE #all_db_permissions

END



GO
