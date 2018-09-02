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
-- Change Log:	Verify SQL versions and engine edition!!...
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_databaseSnapshotCreate] 
	@dbname			SYSNAME		
	, @debugging	BIT		= 0		-- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @timetext			VARCHAR(15)		= [DBA].[dbo].[formatTimeToText]() 
			, @sqlString		NVARCHAR(2000)
			, @ErrorMsg			NVARCHAR(1000)	= N''
			, @snapShotExt		NVARCHAR(3)		= N'.ss'

	DECLARE @InstaceProductVersion		INT = ( SELECT CONVERT(INT, LEFT(CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion')), CHARINDEX('.', CONVERT(NVARCHAR(16), SERVERPROPERTY('ProductVersion'))) - 1)) )
			, @InstanceEngineEdition	INT	= ( SELECT CONVERT(INT, SERVERPROPERTY('EngineEdition')) )

	-- Database snapshots, introduced in SQL Server 2005, are available only in the Enterprise editions of SQL Server 2005 onwards
	IF @InstaceProductVersion < 9 OR @InstanceEngineEdition < 3 BEGIN
		SET @ErrorMsg = N'Database snapshots are available only in the Enterprise editions of SQL Server 2005 onwards'
		RAISERROR(@ErrorMsg, 16, 1, 1)
		RETURN -100
	END 	

	-- Check if the database snapshot matches with the database trying to restore
	IF NOT EXISTS ( SELECT 1 FROM sys.databases WHERE name = @dbname ) BEGIN
		SET @ErrorMsg = N'The Database ' + QUOTENAME(@dbname) + N' does not exist'
		RAISERROR(@ErrorMsg, 16, 1, 1)
		RETURN -200
	END 	

	SET @sqlString	= 'CREATE DATABASE ' + QUOTENAME(@dbname + '_' + @timetext) + ' ON ' + CHAR(10)

	SET @sqlString	+= ( SELECT STUFF( (SELECT CHAR(10) + ', ' + '( NAME = ' + name + ', FILENAME = ''' + DBA.[dbo].[getFilePathFromFullPath](physical_name) + name + '_' + @timetext + @snapShotExt + ''' )'
											FROM sys.master_files
											WHERE database_id = DB_ID(@dbname)
												AND type_desc = 'ROWS'
											FOR XML PATH('') ), 1, 3, '') )

	SET @sqlString	+= CHAR(10) + 'AS SNAPSHOT OF ' + QUOTENAME(@dbname)

	PRINT @sqlString

	IF @debugging = 0 BEGIN
		EXECUTE sp_executesql @sqlString
	END

END




GO
