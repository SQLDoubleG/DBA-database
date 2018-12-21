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
-- Create date: 09/01/2014
-- Description:	Creates a database snapshot for a given database
--
-- Assumptions:	- Snapshot files will be created on the same location as the original database files
--				- Snapshot files will be named after database_file_name_YYYMMDD_hhmm.ss
--
-- Limitations:	Verify SQL versions and engine edition!!...
--
-- Log History:	21/12/2018	RAG	- Converted to script from SP
--								- Changed the Version/Edition check since SQL Server 2016 SP1 introduced snapshots on every edition
--								- Added dependencies
--								- Added support for long SQL statements as result of multiple database files
--
-- =============================================
-- =============================================
-- Dependencies:This Section will create on tempdb any dependant function
-- =============================================
USE [tempdb]
GO
CREATE FUNCTION [dbo].[formatTimeToText]()
RETURNS VARCHAR(15)
AS
BEGIN	
	RETURN LEFT(REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(15),GETDATE(),120), '-', ''), ' ', ''), ':', ''),15)
END
GO
CREATE FUNCTION [dbo].[getFilePathFromFullPath](
	@path NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	DECLARE @slashPos	INT		= CASE WHEN CHARINDEX( '\', REVERSE(@path) ) > 0 THEN LEN(@path) - CHARINDEX( '\', REVERSE(@path) ) + 1 ELSE NULL END
	RETURN ( CASE WHEN @slashPos IS NULL THEN '\' ELSE LEFT( @path, @slashPos ) END )
END
GO
-- =============================================
-- END of Dependencies
-- =============================================
DECLARE	@dbname			SYSNAME	= 'ManyFiles'	
		, @debugging	BIT		= 1		-- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS

SET NOCOUNT ON

DECLARE @timetext			VARCHAR(15)		= [tempdb].[dbo].[formatTimeToText]() 
		, @sqlString		NVARCHAR(MAX)
		, @ErrorMsg			NVARCHAR(1000)	= N''
		, @snapShotExt		NVARCHAR(3)		= N'.ss'

DECLARE @InstaceProductVersion		INT = ( SELECT CONVERT(INT, LEFT(CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion')), CHARINDEX('.', CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion'))) - 1)) )
		, @InstanceEngineEdition	INT	= ( SELECT CONVERT(INT, SERVERPROPERTY('EngineEdition')) )

-- Database snapshots, introduced in SQL Server 2005, are available only in the Enterprise editions of SQL Server 2005 onwards
IF (@InstaceProductVersion BETWEEN 9 AND 12 AND @InstanceEngineEdition < 3) OR @InstaceProductVersion < 9 BEGIN
	SET @ErrorMsg = N'Database snapshots are available only in the Enterprise editions of SQL Server 2005 till 2014, or 2016 onwards any edition'
	RAISERROR(@ErrorMsg, 16, 1, 1)
	GOTO OnError
END 	

-- Check if the database snapshot matches with the database trying to restore
IF NOT EXISTS ( SELECT 1 FROM sys.databases WHERE name = @dbname ) BEGIN
	SET @ErrorMsg = N'The Database ' + QUOTENAME(ISNULL(@dbname,'')) + N' does not exist'
	RAISERROR(@ErrorMsg, 16, 1, 1)
	GOTO OnError
END 	

SET @sqlString	= 'CREATE DATABASE ' + QUOTENAME(@dbname + '_' + @timetext) + ' ON ' + CHAR(10)

SET @sqlString	+= 	( SELECT STUFF(
							(SELECT CONVERT(NVARCHAR(MAX), CHAR(10) + ', ' + '( NAME = ' + QUOTENAME(name) + ', FILENAME = ''' 
									+ [tempdb].[dbo].[getFilePathFromFullPath](physical_name) 
									+ name + '_' + @timetext + @snapShotExt + ''' )')
								FROM sys.master_files
								WHERE database_id = DB_ID(@dbname)
									AND type_desc = 'ROWS'
								FOR XML PATH('') ), 1, 3, '') )

SET @sqlString	+= CHAR(10) + 'AS SNAPSHOT OF ' + QUOTENAME(@dbname)

SELECT CONVERT(XML, '<!--' + CHAR(10) +  @sqlString + CHAR(10) + '-->')

IF @debugging = 0 BEGIN
	EXECUTE sp_executesql @sqlString
END

OnError:
GO
-- =============================================
-- Dependencies:This Section will remove any dependancy
-- =============================================
USE tempdb
GO
DROP FUNCTION [dbo].[formatTimeToText]
GO
DROP FUNCTION [dbo].[getFilePathFromFullPath]
GO

