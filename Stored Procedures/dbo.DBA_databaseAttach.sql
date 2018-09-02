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
-- Create date: 27/02/2015
-- Description:	Retuns the code for Attach/Dettach a database or all user databases if not specified
--
-- Parameters:
--				@dbname
--
-- Log History:	
--				19/06/2015 RAG Changed the datatype returned to be XML due to the limit of 65535 chars outputed for NON XML data
--				11/08/2015 RAG Changed the syntax to use LOG ON (LOGFILE)
-- =============================================
CREATE PROCEDURE [dbo].[DBA_databaseAttach]
	@dbname		SYSNAME = NULL
AS
BEGIN

	SET NOCOUNT ON

	-- Dettach all user databases
	SELECT d.name AS database_name 
			
			, CONVERT(XML, '<!--' + CHAR(10) +
			 'USE [master]' + CHAR(10) + 'GO' + CHAR(10) + 
				'ALTER DATABASE ' + QUOTENAME(name) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'+ CHAR(10) + 'GO' + CHAR(10) + 
				'EXECUTE sp_detach_db ''' + name + '''' + CHAR(10) + 'GO' + CHAR(10) + '-->') AS Dettach_Database
		
	-- Attach all user databases
			, CONVERT(XML, '<!--' + CHAR(10) +
			 'CREATE DATABASE ' + QUOTENAME(name) + ' ON '+ CHAR(10) + CHAR(9) +
				STUFF((SELECT CHAR(10) + CHAR(9) + ', ( FILENAME=''' + physical_name + ''' )'
							FROM sys.master_files as mf
							WHERE mf.database_id = d.database_id
								AND mf.type_desc <> 'LOG'
							FOR XML PATH('')), 1, 4, '') 
						
					+ CHAR(10) + 'LOG ON ' + CHAR(10) + CHAR(9) +

				STUFF((SELECT CHAR(10) + CHAR(9) + ', ( FILENAME=''' + physical_name + ''' )'
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
END



GO
