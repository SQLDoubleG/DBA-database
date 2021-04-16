SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
SET NOCOUNT ON 
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
-- Create date: 27/02/2015
-- Description:	Retuns the code for Attach/Dettach a database or all user databases if not specified
--
-- Parameters:
--				@dbname
--
-- Limitations:	This script will not validate permissions on the directories
--
-- Log History:	
--				19/06/2015	RAG	Changed the datatype returned to be XML due to the limit of 65535 chars outputed for NON XML data
--				11/08/2015	RAG	Changed the syntax to use LOG ON (LOGFILE)
--				06/11/2019	RAG	Changes 
--									- Added parameters @NewDataPath and @NewLogPath
--									- Converted to script
--				06/11/2019	RAG	Changes 
--									- Added parameter parameter @GenerateScript to print out all statments to copy paste
--									- Added validation for @NewDataPath and @NewLogPath
--									- Added functionallity to enable/disable xp_cmdshell to move files
--
-- =============================================
-- =============================================
-- Dependencies:This Section will create on tempdb any dependancy
-- =============================================
USE tempdb
GO
CREATE FUNCTION [dbo].[getFileNameFromPath](
	@path NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	DECLARE @slashPos	INT		= CASE WHEN CHARINDEX( '\', REVERSE(@path) ) > 0 THEN CHARINDEX( '\', REVERSE(@path) ) -1 ELSE LEN(@path) END
	RETURN RIGHT( @path, @slashPos ) 
END
GO
-- =============================================
-- END of Dependencies
-- =============================================

DECLARE	@dbname			SYSNAME			= NULL
DECLARE @NewDataPath 	NVARCHAR(512)	= NULL
DECLARE @NewLogPath 	NVARCHAR(512)	= NULL
DECLARE @GenerateScript	BIT				= 1

--SET @NewDataPath	= CONVERT(NVARCHAR(512), SERVERPROPERTY('InstanceDefaultDataPath'))
--SET @NewLogPath		= CONVERT(NVARCHAR(512), SERVERPROPERTY('InstanceDefaultLogPath'))
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',	N'Software\Microsoft\MSSQLServer\MSSQLServer',	N'DefaultData',	@NewDataPath OUTPUT;
EXEC xp_instance_regread N'HKEY_LOCAL_MACHINE',	N'Software\Microsoft\MSSQLServer\MSSQLServer',	N'DefaultLog',	@NewLogPath OUTPUT;

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

DECLARE @dettach	NVARCHAR(MAX)
DECLARE @move		NVARCHAR(MAX)
DECLARE @attach		NVARCHAR(MAX)
DECLARE @print		NVARCHAR(MAX)

-- Add \ at the end of the path if not null
SET @NewDataPath 	= (CASE WHEN @NewDataPath IS NOT NULL AND RIGHT(@NewDataPath, 1) <> '\' THEN @NewDataPath + '\' ELSE @NewDataPath END)
SET @NewLogPath 	= (CASE WHEN @NewLogPath IS NOT NULL AND RIGHT(@NewLogPath, 1) <> '\' THEN @NewLogPath + '\' ELSE @NewLogPath END)

IF OBJECT_ID('tempdb..#direxist')	IS NOT NULL DROP TABLE #direxist
IF OBJECT_ID('tempdb..#output')		IS NOT NULL DROP TABLE #output

CREATE TABLE #direxist(
	File_Exists					BIT
	, File_is_a_Directory		BIT
	, Parent_Directory_Exists	BIT
)

IF @NewDataPath IS NOT NULL	BEGIN	
	INSERT #direxist (File_Exists, File_is_a_Directory, Parent_Directory_Exists)
	EXEC xp_fileexist @NewDataPath

	IF NOT EXISTS (SELECT * FROM #direxist WHERE File_is_a_Directory = 1) BEGIN
		RAISERROR ('New Data Path not valid %s',16,0,@NewDataPath) 
		RETURN		
	END
END

IF @NewLogPath IS NOT NULL BEGIN
	TRUNCATE TABLE #direxist

	INSERT #direxist (File_Exists, File_is_a_Directory, Parent_Directory_Exists)
	EXEC xp_fileexist @NewLogPath

	IF NOT EXISTS (SELECT * FROM #direxist WHERE File_is_a_Directory = 1) BEGIN
		RAISERROR ('New Log Path not valid %s',16,0,@NewLogPath)
		RETURN
	END
END

DECLARE @xp_cmdshell_orig bit;
DECLARE @reconfigure_ok bit;

SELECT @xp_cmdshell_orig = CONVERT(bit, value_in_use)
	FROM sys.configurations
	WHERE name = 'xp_cmdshell';

SELECT @reconfigure_ok = (CASE WHEN EXISTS (SELECT *
											FROM sys.configurations
											WHERE value <> value_in_use
												AND NOT	(
													name = 'min server memory (MB)'
													AND value = 0
													AND value_in_use = 16))	THEN 0 
							ELSE 1
						END)

SELECT d.name AS database_name 
	-- Dettach all user databases
		, CONVERT(NVARCHAR(MAX), CHAR(10) + 
			'USE [master]' + CHAR(10) + 
			'ALTER DATABASE ' + QUOTENAME(name) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'+ CHAR(10) + 
			'EXECUTE sp_detach_db ''' + name + '''' + CHAR(10)) AS Dettach_Database
	-- Move files 
		, CONVERT(NVARCHAR(MAX), CHAR(10) + 
				STUFF((SELECT CHAR(10) + 'EXECUTE xp_cmdshell ''move "' + mf.physical_name + '" "' 
					+ @NewDataPath + [tempdb].[dbo].[getFileNameFromPath](physical_name) + '"'''
						FROM sys.master_files as mf
						WHERE mf.database_id = d.database_id
							AND mf.type_desc <> 'LOG'
							FOR XML PATH('')), 1, 1, '') 
				+ CHAR(10) +
				STUFF((SELECT CHAR(10) + 'EXECUTE xp_cmdshell ''move "' + mf.physical_name + '" "' 
					+ @NewLogPath + [tempdb].[dbo].[getFileNameFromPath](physical_name) + '"'''
						FROM sys.master_files as mf
						WHERE mf.database_id = d.database_id
							AND mf.type_desc = 'LOG'
							FOR XML PATH('')), 1, 1, '') 
				+ CHAR(10))  AS Move_Files
	-- Attach all user databases
		, CONVERT(NVARCHAR(MAX), CHAR(10) + 
			'USE [master]' + CHAR(10) + 
			'CREATE DATABASE ' + QUOTENAME(name) + ' ON '+ CHAR(10) + CHAR(9) +
			STUFF((SELECT CHAR(10) + CHAR(9) + ', ( FILENAME=''' + 
														CASE WHEN @NewDataPath IS NOT NULL THEN @NewDataPath + [tempdb].[dbo].[getFileNameFromPath](physical_name)
															ELSE physical_name														
														END + ''' )'
						FROM sys.master_files as mf
						WHERE mf.database_id = d.database_id
							AND mf.type_desc <> 'LOG'
						FOR XML PATH('')), 1, 4, '') 
					
				+ CHAR(10) + 'LOG ON ' + CHAR(10) + CHAR(9) +

			STUFF((SELECT CHAR(10) + CHAR(9) + ', ( FILENAME=''' + 
														CASE WHEN @NewDataPath IS NOT NULL THEN @NewLogPath + [tempdb].[dbo].[getFileNameFromPath](physical_name)
															ELSE physical_name														
														END + ''' )'
						FROM sys.master_files as mf
						WHERE mf.database_id = d.database_id
							AND mf.type_desc = 'LOG'
						FOR XML PATH('')), 1, 4, '') 						
					+ ' FOR ATTACH' + CHAR(10) + 			
				'USE [master]' + CHAR(10) + 
				'ALTER DATABASE ' + QUOTENAME(name) + ' SET MULTI_USER WITH ROLLBACK IMMEDIATE'+ CHAR(10)) AS Attach_Database
	INTO #output
	FROM sys.databases AS d 
	WHERE database_id > 4
		AND name = ISNULL(@dbname, name)

IF @GenerateScript = 1 BEGIN
	SET @print = '--============== SERVER ' + QUOTENAME(CONVERT(NVARCHAR(512), SERVERPROPERTY('ComputerNamePhysicalNetBios'))) + ' =======================' + CHAR(10)
	SET @print += ':CONNECT ' + QUOTENAME(CONVERT(NVARCHAR(512), SERVERPROPERTY('ComputerNamePhysicalNetBios'))) + CHAR(10)

	IF @xp_cmdshell_orig = 0 AND @reconfigure_ok = 1 BEGIN
	   SET @print += '-- Enabling temporarily ''xp_cmdshell''' + CHAR(10)
	   SET @print += 'EXEC sp_configure ''show advanced options'', 1;' + CHAR(10)
	   SET @print += 'RECONFIGURE;' + CHAR(10)
	   SET @print += 'EXEC sp_configure ''xp_cmdshell'', 1;' + CHAR(10)
	   SET @print += 'RECONFIGURE;' + CHAR(10)
	END
		
	DECLARE c CURSOR FOR 
		SELECT database_name
				, CONVERT(NVARCHAR(MAX), Dettach_Database)
				, CONVERT(NVARCHAR(MAX), Move_Files)
				, CONVERT(NVARCHAR(MAX), Attach_Database) 
			FROM #output ORDER BY database_name
	OPEN c
	FETCH NEXT FROM c INTO @dbname, @dettach, @move, @attach
	WHILE @@FETCH_STATUS = 0 BEGIN

		SET @print += '--============== DATABASE ' + QUOTENAME(@dbname) + ' =======================' + CHAR(10)
		SET @print += @dettach 
		SET @print += ISNULL(@move, '-- Files is current location') 
		SET @print += @attach + CHAR(10)

		FETCH NEXT FROM c INTO @dbname, @dettach, @move, @attach
	END
	CLOSE c
	DEALLOCATE c

	IF @xp_cmdshell_orig = 0 AND @reconfigure_ok = 1 BEGIN
	   SET @print += '-- Reverting ''xp_cmdshell'', 0;' + CHAR(10)
	   SET @print += 'EXEC sp_configure ''xp_cmdshell'', 0;' + CHAR(10)
	   SET @print += 'RECONFIGURE;' + CHAR(10)
	END

	SET @print += 'GO' + CHAR(10)
	PRINT @print

END
ELSE BEGIN
	SELECT database_name
			, CONVERT(XML, '<!--' + Dettach_Database			+ '-->') AS Dettach_Database
			, CONVERT(XML, '<!--' + ISNULL(Move_Files, CHAR(10))+ '-->') AS Move_Files
			, CONVERT(XML, '<!--' + Attach_Database				+ '-->') AS Attach_Database
		FROM #output 
		ORDER BY database_name
END

GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[getFileNameFromPath]
GO
