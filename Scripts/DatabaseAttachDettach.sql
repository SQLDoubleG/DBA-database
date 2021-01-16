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
-- Log History:	
--				19/06/2015 RAG Changed the datatype returned to be XML due to the limit of 65535 chars outputed for NON XML data
--				11/08/2015 RAG Changed the syntax to use LOG ON (LOGFILE)
--				06/11/2019 RAG Changes 
--								- Added parameters @NewDataPath and @NewLogPath
--								- Converted to script
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

DECLARE	@dbname			SYSNAME = NULL
DECLARE @NewDataPath 	NVARCHAR(512) = NULL
DECLARE @NewLogPath 	NVARCHAR(512) = NULL

-- Add \ at the end of the path if not null
SET @NewDataPath 	= (CASE WHEN @NewDataPath IS NOT NULL AND RIGHT(@NewDataPath, 1) <> '\' THEN @NewDataPath + '\' ELSE @NewDataPath END)
SET @NewLogPath 	= (CASE WHEN @NewLogPath IS NOT NULL AND RIGHT(@NewLogPath, 1) <> '\' THEN @NewLogPath + '\' ELSE @NewLogPath END)

-- Dettach all user databases
SELECT d.name AS database_name 
		
		, CONVERT(XML, '<!--' + CHAR(10) +
			'USE [master]' + CHAR(10) + 'GO' + CHAR(10) + 
			'ALTER DATABASE ' + QUOTENAME(name) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'+ CHAR(10) + 'GO' + CHAR(10) + 
			'EXECUTE sp_detach_db ''' + name + '''' + CHAR(10) + 'GO' + CHAR(10) + '-->') AS Dettach_Database
	
-- Attach all user databases
		, CONVERT(XML, '<!--' + CHAR(10) +
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
			
			'USE [master]' + CHAR(10) + 'GO' + CHAR(10) + 
			'ALTER DATABASE ' + QUOTENAME(name) + ' SET MULTI_USER WITH ROLLBACK AFTER 10'+ CHAR(10) + 'GO' + CHAR(10) + '-->') AS Attach_Database
	FROM sys.databases AS d 
	WHERE database_id > 4
		AND name = ISNULL(@dbname, name)
	ORDER BY name
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[getFileNameFromPath]
GO
