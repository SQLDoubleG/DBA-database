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
-- Author:		RAG 
-- Create date: 12/12/2016 
-- Description:	Run DBCC CHECKTABLE for a given table or all tables in a database 
-- 
-- Assumptions: This sp can be used independantly or called from within [DBA_runCHECKDB] 
-- 
-- Log History:	 
--				12/12/2016	RAG - Created 
----  
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_runCHECKTABLE] 
	@dbname				SYSNAME 
	, @tableName		SYSNAME = NULL 
	, @noIndex			BIT		= 0 
	, @tabLock			BIT		= 0 
	, @debugging		BIT		= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS 
	, @errorNumber		INT OUTPUT 
	, @errorMessage		NVARCHAR(4000) OUTPUT 
AS 
BEGIN 
 
	SET NOCOUNT ON 
 
	DECLARE @sqlString		NVARCHAR(MAX) 
			, @emailBody	NVARCHAR(1000) 
 
	-- Adjust parameters 
	SET @noIndex		= ISNULL(@noIndex, 0) 
	SET @tabLock		= ISNULL(@tabLock, 0) 
	SET @debugging		= ISNULL(@debugging, 0) 
 
	IF NOT EXISTS (SELECT db.[name] FROM sys.databases AS db WHERE db.[name] = ISNULL(@dbname, '')) BEGIN 
		RAISERROR ('The value specified for @dbname is not valid database name on this instance, please specify a valid value', 16, 0) 
		RETURN -100 
	END  
	 
 
	SET @sqlString = N'USE ' + QUOTENAME(@dbname) + CHAR(10) + N' 
 
	DECLARE @sql NVARCHAR(1000) = N'''' 
 
	DECLARE tbs CURSOR LOCAL READ_ONLY FORWARD_ONLY FAST_FORWARD FOR 
		SELECT OBJECT_SCHEMA_NAME(object_id) + ''.'' + name FROM sys.all_objects  
			WHERE ( type = ''U'' OR ( type = ''V'' AND OBJECTPROPERTYEX(object_id, ''IsIndexed'') = 1))				 
				AND name = ISNULL(@tableName, name) 
	 
	OPEN tbs 
 
	FETCH NEXT FROM tbs INTO @tableName 
 
	WHILE @@FETCH_STATUS = 0 BEGIN 
 
		SET @sql = N''DBCC CHECKTABLE (''+ QUOTENAME(@tableName)	+ CASE WHEN @noIndex = 1 THEN '', NOINDEX'' ELSE '''' END + 
							'') WITH ALL_ERRORMSGS, NO_INFOMSGS''	+ CASE WHEN @tabLock = 1 THEN '', TABLOCK'' ELSE '''' END 
 
		 
		PRINT ''Executing ... '' + @sql 
		 
		IF @debugging = 0 BEGIN 
			BEGIN TRY 
				EXECUTE sp_executesql @sql 
			END TRY 
			BEGIN CATCH 
				PRINT ''Failed to execute '' + @sql 
			END CATCH 
		END 
 
		FETCH NEXT FROM tbs INTO @tableName 
 
	END 
	 
	CLOSE tbs 
	DEALLOCATE tbs' 
 
	BEGIN TRY 
		EXEC sp_executesql  
				@stmt			= @sqlString 
				, @params		= N'@sqlString NVARCHAR(MAX), @tableName SYSNAME, @noIndex BIT, @tabLock BIT, @debugging BIT' 
				, @sqlString	= @sqlString 
				, @tableName	= @tableName 
				, @noIndex		= @noIndex 
				, @tabLock		= @tabLock 
				, @debugging	= @debugging 
	END TRY 
	BEGIN CATCH 		 
			 
		IF (SELECT CURSOR_STATUS('local', 'tbs')) IN (0,1) BEGIN 
			CLOSE tbs 
			DEALLOCATE tbs 
		END 
 
		SELECT @errorNumber		= ERROR_NUMBER() 
				, @errorMessage = ERROR_MESSAGE() 
 
		SET @emailBody = @@SERVERNAME + ', ' + @dbname + CHAR(10) + '. The application returned the following error:' + CHAR(10) + @errorMessage 
				 
		EXEC msdb.dbo.sp_send_dbmail	 
			@profile_name	= 'Admin Profile',  
			@recipients		= 'DatabaseAdministrators@rws.com',  
			@subject		= 'DBCC CHECKTABLE Failed',  
			@body			= @emailBody 
 
		RETURN -300 
 
	END CATCH 
 
END 
GO
