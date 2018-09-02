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
-- Create date: 08/10/2013
-- Description:	Returns the list of backup files (*.bak, *.trn) files from a given list of files
--
-- Parameters:	
--				- @path NVARCHAR(512)	-- database's backups path 
--
-- Assumptions:	
--				- Full backups have ".bak" extension
--				- Differential backups have ".diff" extension
--				- transaction log backups ".trn"
--
-- Change Log:	
--
--				20/04/2016	RAG	- Added \ at the end of the path if not present
--								- Back to filtering only backup files
-- =============================================
CREATE PROCEDURE [dbo].[DBA_getBackupFilesList] 
	@path NVARCHAR(512)
	, @order NVARCHAR(5) = 'ASC'
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @BackupFileList	TABLE (
			ID				INT IDENTITY
			, [FileName]	NVARCHAR(256))

	DECLARE @dirCmd			NVARCHAR(1000)
			, @errorMsg		NVARCHAR(1000)

	-- Add \ to path if not present
	SET @path = CASE WHEN RIGHT(@path, 1) <> '\' THEN @path + '\' ELSE @path END

	-- Files are ordered by date asc + alphabetically asc (in case backups are distributed in multiple files with exactly same date)
	SET @dirCmd = 'dir /B ' + CASE WHEN @order = 'ASC' THEN '/ODN' ELSE '/O-D-N' END + ' "' + @path + '*.bak" "'  + @path + '*.diff" "' + @path + '*.trn"'
	--SET @dirCmd = 'dir /B ' + CASE WHEN @order = 'ASC' THEN '/ODN' ELSE '/O-D-N' END + ' "' + @path + '*.*"'
	
	PRINT '--' + @dirCmd 

	-- Gets the list of files in the directory sorted by date (oldest first)
	-- We will delete all files till the last FULL BACKUP
	EXEC master.dbo.xp_cmdshell @dirCmd
END



GO
