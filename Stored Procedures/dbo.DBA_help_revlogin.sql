SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
-- ============================================= 
-- Author:		Microsoft  
-- 
-- Original URL: http://support.microsoft.com/kb/918992 
-- 
-- Description: Scripts out Logins to be moved from one server to another 
-- 
-- Dependencies: This SP depends on DBA.dbo.[DBA_hexadecimal] (originally named [sp_hexadecimal]) 
-- 
-- Log History: 
--				09/09/2014 RAG - Added functionality to script server roles membership 
--				19/09/2016 SZO - Changed "CURSOR" for a "CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD" 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_help_revlogin]  
	@login_name sysname = NULL  
AS 
BEGIN 
	 
	SET NOCOUNT ON 
 
	DECLARE @name					SYSNAME 
	DECLARE @type					VARCHAR (1) 
	DECLARE @hasaccess				INT 
	DECLARE @denylogin				INT 
	DECLARE @is_disabled			INT 
	DECLARE @server_roles			NVARCHAR(4000) 
	DECLARE @PWD_varbinary			VARBINARY (256) 
	DECLARE @PWD_string				VARCHAR (514) 
	DECLARE @SID_varbinary			VARBINARY (85) 
	DECLARE @SID_string				VARCHAR (514) 
	DECLARE @tmpstr					VARCHAR (1024) 
	DECLARE @is_policy_checked		VARCHAR (3) 
	DECLARE @is_expiration_checked	VARCHAR (3) 
	DECLARE @defaultdb				SYSNAME 
  
	--SELECT p.sid, p.name, p.type, p.is_disabled, p.default_database_name, l.hasaccess, l.denylogin  
	--	FROM sys.server_principals p  
	--		LEFT JOIN sys.syslogins l 
	--			ON ( l.name = p.name )  
	--	WHERE p.type IN ( 'S', 'G', 'U' ) AND p.name <> 'sa' 
	--	ORDER BY p.name 
	 
	IF (@login_name IS NULL) 
		DECLARE login_curs CURSOR LOCAL FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
			SELECT p.sid, p.name, p.type, p.is_disabled, p.default_database_name, l.hasaccess, l.denylogin  
					,ISNULL(STUFF( (SELECT CHAR(10) +  
												CASE WHEN DBA.dbo.getNumericSQLVersion(NULL) >= 11 THEN 'ALTER ROLE '  + QUOTENAME(name) + ' ADD MEMBER ' + QUOTENAME(p.name)  
													ELSE 'EXECUTE sp_addsrvrolemember ' + QUOTENAME(p.name) + ', ' + QUOTENAME(name) 
												END			 
											+ CHAR(10) + 'GO' 
										FROM sys.server_role_members AS rm 
											INNER JOIN sys.server_principals AS r 
												ON r.principal_id = rm.role_principal_id 
													AND r.type = 'R' 
										WHERE rm.member_principal_id = p.principal_id 
										FOR XML PATH('')), 1, 1, ''), '') AS serverRoles 
				FROM sys.server_principals p  
					LEFT JOIN sys.syslogins l 
						ON ( l.name = p.name )  
				WHERE p.type IN ( 'S', 'G', 'U' ) AND p.name <> 'sa' 
				ORDER BY p.name 
	ELSE 
		DECLARE login_curs CURSOR FORWARD_ONLY READ_ONLY FAST_FORWARD FOR 
			SELECT p.sid, p.name, p.type, p.is_disabled, p.default_database_name, l.hasaccess, l.denylogin  
					,ISNULL(STUFF( (SELECT CHAR(10) +  
												CASE WHEN DBA.dbo.getNumericSQLVersion(NULL) >= 11 THEN 'ALTER ROLE '  + QUOTENAME(name) + ' ADD MEMBER ' + QUOTENAME(p.name)  
													ELSE 'EXECUTE sp_addsrvrolemember ' + QUOTENAME(p.name) + ', ' + QUOTENAME(name) 
												END			 
											+ CHAR(10) + 'GO' 
										FROM sys.server_role_members AS rm 
											INNER JOIN sys.server_principals AS r 
												ON r.principal_id = rm.role_principal_id 
													AND r.type = 'R' 
										WHERE rm.member_principal_id = p.principal_id 
										FOR XML PATH('')), 1, 1, ''), '') AS serverRoles 
				FROM sys.server_principals p  
					LEFT JOIN sys.syslogins l 
						ON ( l.name = p.name )  
				WHERE p.type IN ( 'S', 'G', 'U' )  
					AND p.name = @login_name 
	 
	OPEN login_curs 
 
	FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @type, @is_disabled, @defaultdb, @hasaccess, @denylogin, @server_roles 
	IF (@@fetch_status = -1) BEGIN 
		PRINT 'No login(s) found.' 
		CLOSE login_curs 
		DEALLOCATE login_curs 
		RETURN -1 
	END 
	SET @tmpstr = '/* sp_help_revlogin script ' 
	PRINT @tmpstr 
	SET @tmpstr = '** Generated ' + CONVERT (varchar, GETDATE()) + ' on ' + @@SERVERNAME + ' */' 
	PRINT @tmpstr 
	PRINT '' 
	WHILE (@@fetch_status <> -1) BEGIN 
		IF (@@fetch_status <> -2) BEGIN 
			PRINT '' 
			SET @tmpstr = '-- Login: ' + @name 
			PRINT @tmpstr 
			IF (@type IN ( 'G', 'U')) BEGIN -- NT authenticated account/group 
				SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME( @name ) + ' FROM WINDOWS WITH DEFAULT_DATABASE = [' + @defaultdb + ']' 
			END 
			ELSE BEGIN -- SQL Server authentication 
				-- obtain password and sid 
				SET @PWD_varbinary = CAST( LOGINPROPERTY( @name, 'PasswordHash' ) AS varbinary (256) ) 
				EXEC DBA.dbo.[DBA_hexadecimal] @PWD_varbinary, @PWD_string OUT 
				EXEC DBA.dbo.[DBA_hexadecimal] @SID_varbinary,@SID_string OUT 
  
				-- obtain password policy state 
				SELECT @is_policy_checked = CASE is_policy_checked WHEN 1 THEN 'ON' WHEN 0 THEN 'OFF' ELSE NULL END FROM sys.sql_logins WHERE name = @name 
				SELECT @is_expiration_checked = CASE is_expiration_checked WHEN 1 THEN 'ON' WHEN 0 THEN 'OFF' ELSE NULL END FROM sys.sql_logins WHERE name = @name 
  
				SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME( @name ) + ' WITH PASSWORD = ' + @PWD_string + ' HASHED, SID = ' + @SID_string + ', DEFAULT_DATABASE = [' + @defaultdb + ']' 
 
				IF ( @is_policy_checked IS NOT NULL ) BEGIN 
					SET @tmpstr = @tmpstr + ', CHECK_POLICY = ' + @is_policy_checked 
				END 
				IF ( @is_expiration_checked IS NOT NULL ) BEGIN 
					SET @tmpstr = @tmpstr + ', CHECK_EXPIRATION = ' + @is_expiration_checked 
				END 
			END 
			IF (@denylogin = 1) BEGIN -- login is denied access 
				SET @tmpstr = @tmpstr + '; DENY CONNECT SQL TO ' + QUOTENAME( @name ) 
			END 
			ELSE IF (@hasaccess = 0) BEGIN -- login exists but does not have access 
				SET @tmpstr = @tmpstr + '; REVOKE CONNECT SQL TO ' + QUOTENAME( @name ) 
			END 
			IF (@is_disabled = 1) BEGIN -- login is disabled 
				SET @tmpstr = @tmpstr + '; ALTER LOGIN ' + QUOTENAME( @name ) + ' DISABLE' 
			END 
			PRINT @tmpstr + CHAR(10) + 'GO' + CHAR(10) + @server_roles 
		END 
 
		FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @type, @is_disabled, @defaultdb, @hasaccess, @denylogin, @server_roles 
	END 
	CLOSE login_curs 
	DEALLOCATE login_curs 
	RETURN 0 
END 
 
 
GO
