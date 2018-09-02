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
-- Description:	Restores a database from a given database snapshot 
--
-- Assumptions:	
--
-- Change Log:	
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_databaseSnapshotRestore] 
	@snapshotName			SYSNAME		
	, @dbname				SYSNAME		
	, @deleteOtherSnapshots	BIT = NULL
	, @debugging			BIT		= 0		-- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @timetext			VARCHAR(15)		= [DBA].[dbo].[formatTimeToText]() 
			, @sqlDeleteSS		NVARCHAR(2000)	= N'USE [master]'
			, @sqlRestore		NVARCHAR(2000)	= N'USE [master]'
			, @ErrorMsg			NVARCHAR(1000)	= N''
	
	
	-- Check if the database snapshot matches with the database trying to restore
	IF NOT EXISTS ( SELECT 1 FROM sys.databases WHERE name = @snapshotName AND source_database_id = DB_ID(@dbname) ) BEGIN
		SET @ErrorMsg = N'The Snapshot ' + QUOTENAME(@snapshotName) + N' does not exist or does not belong to the database ' + QUOTENAME(@dbname)
		RAISERROR(@ErrorMsg, 16, 1, 1)
		RETURN -100
	END 
	
	-- Check if there are more database snapshots for the database trying to restore
	IF EXISTS ( SELECT 1 FROM sys.databases WHERE name <> @snapshotName AND source_database_id = DB_ID(@dbname) AND ISNULL(@deleteOtherSnapshots, 0) = 0 ) BEGIN
		SET @ErrorMsg = N'There are more Snapshots apart from ' + QUOTENAME(@snapshotName) + N' for the database ' + QUOTENAME(@dbname) + 
							CHAR(10) + N'Please specify @deleteOtherSnapshots = 1 When calling the SP'
		RAISERROR(@ErrorMsg, 16, 1, 1)
		RETURN -200
	END 

	-- Get other snapshots for the same database to delete them
	SET @sqlDeleteSS += ( SELECT CHAR(10) + N'DROP DATABASE ' + QUOTENAME(name)
								FROM sys.databases 
								WHERE name <> @snapshotName AND source_database_id = DB_ID(@dbname) 
								FOR XML PATH('') )
	
	-- Restore database from snapshot
	SET @sqlRestore += CHAR(10) + N'ALTER DATABASE '	+ QUOTENAME(@dbname) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE'
	SET @sqlRestore += CHAR(10) + N'RESTORE DATABASE '	+ QUOTENAME(@dbname) + N' FROM DATABASE_SNAPSHOT = ''' + @snapshotName + N''''
	SET @sqlRestore += CHAR(10) + N'ALTER DATABASE '	+ QUOTENAME(@dbname) + N' SET MULTI_USER'

	PRINT @sqlDeleteSS
	PRINT @sqlRestore

	IF @debugging = 0 BEGIN
		EXECUTE sp_executesql @sqlDeleteSS
		EXECUTE sp_executesql @sqlRestore
	END

END




GO
