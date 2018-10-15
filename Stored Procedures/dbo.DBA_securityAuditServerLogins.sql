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
-- Create date: 28/06/2013
-- Description:	Returns Server Login information
--				This SP returns
--					- Server logins with server roles and permissions, logins included if it's a Windows Group, groups the login belong to and database users mapped to the login
--
-- Change log:	04/03/2014 RAG	- Removed the last 2 resultsets and included that info into que main one, columns [IncludedLogins] and [IncludedInWindowsGroups]
--								- Functionality to search a AD user when is included in a Windows Group
--				15/05/2014 RAG	- Included list of database users the login is mapped to 
--				09/09/2014 RAG	- Added column CREATE_LOGIN, which contain the script required to recreate the login and its server roles if any
--				13/05/2016 RAG	- Fixed bug when scripting server roles
--				14/03/2017 RAG	- Removed deprecated view syslogins
--								- Added state_desc to the permisssion list (DENY, REVOKE, GRANT, GRANT_WITH_GRANT_OPTION)
--								- Added server permisssions to the CREATE LOGIN statement
--				30/04/2018 RAG	- Added check for existance to the CREATE_LOGIN statement
--								- Don't script [sa] login
--				11/10/2018 RAG 	- Added try catch block to handle windows groups that fail to get information
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_securityAuditServerLogins]
	@loginName	SYSNAME = NULL
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @sqlString		NVARCHAR(4000)
	DECLARE @errMsg			NVARCHAR(4000)

	DECLARE @groupName		SYSNAME
			, @numGroups	INT
			, @countGroups	INT = 1

	CREATE TABLE #usersInGroups (
		accountName			SYSNAME
		, [Type]			SYSNAME
		, [privilege]		SYSNAME
		, [mappedLogin]		SYSNAME
		, [permissionPath]	SYSNAME)

	CREATE TABLE #allDbUsers(
		database_name		SYSNAME
		, database_username SYSNAME
		, sid				VARBINARY(85)
	)

	DECLARE @GO				CHAR(4) = CHAR(10) + 'GO' + CHAR(10)

	SELECT IDENTITY(INT, 1, 1) AS ID
			, name AS GroupName
		INTO #windowsGroups
		FROM sys.server_principals AS sp
		WHERE sp.type = 'G'
			AND name NOT LIKE 'NT SERVICE\%'

	SET @numGroups = @@ROWCOUNT

	WHILE @countGroups <= @numGroups BEGIN
		SELECT @groupName = GroupName
			FROM #windowsGroups
			WHERE ID = @countGroups

		SET @sqlString = 'EXEC XP_LOGININFO ' + QUOTENAME(@groupName) + ', [members]'

		BEGIN TRY
			INSERT INTO #usersInGroups
				EXECUTE sp_executesql @sqlString 
		END TRY
		BEGIN CATCH
			SET @errMsg = 'There was an error retrieving information for Windows AD Group ' + QUOTENAME(@groupName);
			PRINT @errMsg;
		END CATCH

		SET @countGroups += 1

	END

	-- Get all DB users
	EXECUTE sp_MSforeachdb N'
		USE [?]
		INSERT INTO #allDbUsers
			SELECT DB_NAME() AS database_name
					, name AS database_username
					, sid AS principal_sid
				FROM sys.database_principals
				WHERE is_fixed_role = 0
					AND type <> ''R''
					AND sid IS NOT NULL
					AND name NOT IN (''guest'')
	'

	-- All server logins with their server roles
	SELECT @@SERVERNAME AS ServerName
			, sp.principal_id 
			, sp.name AS LoginName
			, sp.type_desc AS LoginType
			, CASE WHEN sp.is_disabled = 1 THEN 'Yes' ELSE 'No' END AS IsDisabled
			, sp.default_database_name
			, STUFF((SELECT ', ' + sp2.name
						FROM sys.server_role_members AS srm
							LEFT JOIN sys.server_principals AS sp2
								ON sp2.principal_id = srm.role_principal_id
						WHERE srm.member_principal_id = sp.principal_id
						FOR XML PATH('')), 1, 2, '') AS ServerRoles
			, STUFF((SELECT ', ' + p.state_desc + ' ' + p.permission_name 
						FROM sys.server_permissions AS p
						WHERE p.grantee_principal_id = sp.principal_id 
						FOR XML PATH('')), 1, 2, '') AS ServerPermissions				
			, STUFF( (SELECT ', ' + QUOTENAME(mappedLogin) 
						FROM #usersInGroups AS u WHERE u.permissionPath = sp.name ORDER BY mappedLogin FOR XML PATH('')), 1, 2, '') AS IncludedLogins
			, STUFF( (SELECT ', ' + QUOTENAME(permissionPath) 
						FROM #usersInGroups AS u WHERE u.mappedLogin = sp.name ORDER BY permissionPath FOR XML PATH('')), 1, 2, '') AS IncludedInWindowsGroups
			, STUFF( (SELECT ', ' + QUOTENAME(database_name) + '.' + QUOTENAME(database_username) 
						FROM #allDbUsers AS u WHERE u.sid = sp.sid ORDER BY database_name FOR XML PATH('')), 1, 2, '') AS MappedToDBuser
			, STUFF((SELECT @GO + 
								CASE WHEN [dbo].[getNumericSQLVersion](NULL) >= 11 THEN 'ALTER SERVER ROLE ' + QUOTENAME(sp2.name) + ' DROP MEMBER ' + QUOTENAME(sp.name)
									ELSE 'EXECUTE sys.sp_dropsrvrolemember ' + QUOTENAME(sp.name) + ', ' + QUOTENAME(sp2.name) 
								END
						FROM sys.server_role_members AS srm
							LEFT JOIN sys.server_principals AS sp2
								ON sp2.principal_id = srm.role_principal_id
						WHERE srm.member_principal_id = sp.principal_id
						FOR XML PATH('')), 1, 4, '') AS DROP_SERVER_ROLE
			,	
			CASE WHEN sp.name = 'sa' THEN ''
				ELSE 			
				'USE [master]' + @GO
				+ 'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = ''' + sp.name + ''') BEGIN' + CHAR(10)
				
				+ CASE 
					WHEN sp.type IN ('U', 'G') THEN 'CREATE LOGIN ' + QUOTENAME(sp.name) + ' FROM WINDOWS WITH DEFAULT_DATABASE = ' + QUOTENAME(sp.default_database_name)
					ELSE 'CREATE LOGIN ' + QUOTENAME(sp.name) + ' WITH PASSWORD = ' + DBA.dbo.hexadecimal(CAST( LOGINPROPERTY( sp.name, 'PasswordHash' ) AS VARBINARY (256) )) + 
						' HASHED, SID = ' + DBA.dbo.hexadecimal(sp.sid) + ', DEFAULT_DATABASE = '  + QUOTENAME(sp.default_database_name) +
					', CHECK_POLICY = ' + CASE WHEN sqll.is_policy_checked = 1 THEN 'ON' ELSE 'OFF' END + 
					', CHECK_EXPIRATION = ' + CASE WHEN sqll.is_expiration_checked = 1 THEN 'ON' ELSE 'OFF' END + CHAR(10)
					+ (SELECT p.state_desc + ' ' + p.permission_name + ' TO ' + QUOTENAME(sp.name) + CHAR(10) AS [text()]
								FROM sys.server_permissions AS p
								WHERE p.grantee_principal_id = sp.principal_id 
								FOR XML PATH(''))
				END + CHAR(10)
				+ 'END' + CHAR(10)
				+ CASE WHEN sp.is_disabled = 1 THEN 'ALTER LOGIN ' + QUOTENAME(sp.name) + ' DISABLE' + @GO ELSE '' END +
					ISNULL(STUFF( (SELECT CHAR(10) + 
											CASE WHEN DBA.dbo.getNumericSQLVersion(NULL) >= 11 THEN 'ALTER SERVER ROLE '  + QUOTENAME(name) + ' ADD MEMBER ' + QUOTENAME(sp.name) 
												ELSE 'EXECUTE sp_addsrvrolemember ' + QUOTENAME(sp.name) + ', ' + QUOTENAME(name)
											END			
										+ CHAR(10) + 'GO'
									FROM sys.server_role_members AS rm
										INNER JOIN sys.server_principals AS r
											ON r.principal_id = rm.role_principal_id
												AND r.type = 'R'
									WHERE rm.member_principal_id = sp.principal_id
									FOR XML PATH('')), 1, 1, ''), '') 
			END AS CREATE_LOGIN

		FROM sys.server_principals AS sp
			LEFT JOIN sys.sql_logins AS sqll
				ON sqll.sid = sp.sid
		WHERE sp.type <> 'R' -- R = Server role
			AND sp.name NOT LIKE '#%#'
			AND sp.name NOT LIKE 'NT %\%'
			AND ( sp.name LIKE ISNULL(@loginName, sp.name)
					-- Lookup for the given login within all windows groups in the server
					OR EXISTS ( SELECT 1 FROM #usersInGroups AS uig WHERE uig.permissionPath = sp.name AND uig.mappedLogin LIKE ISNULL(@loginName, uig.mappedLogin) ) )
		ORDER BY ServerRoles DESC
			, LoginType ASC
			, LoginName ASC

	DROP TABLE #windowsGroups
	DROP TABLE #usersInGroups
END
GO
