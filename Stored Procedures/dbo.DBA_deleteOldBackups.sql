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
-- Create date: 07/10/2013
-- Description:	Delete old backups for a given database or all databases within a given instance
--				This Script does:
--					- Delete old backups and transaction logs according the parameter keepNbackups or the setting defined in DBA.dbo.DatabaseInformation.keepNbackups 
--					- This logic has been moved from the sp DBA.dbo.DBA_runFullBackup which from now on will call this sp in case is required
--					- This sp can be called right after performing a new full backup or after running CHECKDB on the last backup (PB), 
--						so we can avoid having three copies of each database to run CHECKDB on backups and not on the online databases
--
-- Parameters:	
--				- @instanceName, optional, if not provided will take the current instance (Note that some backup paths might not be accessible from other servers)
--				- @dbname, optional, if not provided will loop through all dbs defined for the server in DBA.dbo.DatabaseInformation
--				- @keepNbackups, optional, if not provided will get the value defined for the database in DBA.dbo.DatabaseInformation
--				- @includeMockFile, optional, if provided with value 1, will include a fake file in the list as if it is the last backup to display good results when debugging
--				- @debugging, optional, if not provided or 0, the sp will execute the actions, otherwise just will print out the statements for debugging
--
-- Assumptions:	
--				- Full backups have ".bak" extension and transaction log backups ".trn"
--				- Backup Path will be taken by calling the function [DBA].[dbo].[getBackupRootPath]
--				- Old backups will be deleted according to the value of [DBA].[dbo].[DatabaseInformation] column [keepNbackups] 
--					or [DBA].[dbo].[InstanceInformation] column [keepNbackups].
--					If it's not defined at DB level will take the value defined at Instance Level (defaulted to 1)
--
-- Change Log:	
--				19/04/2016	RAG	Changed how the min backup is calculated to take _YYYYMMDD_hhmiss instead of only _YYYYMMDD (9 -> 16)
--									This was making problems when more than 1 full backup was taken the same day 
--				17/06/2016	RAG	Changed [backupPath] to NVARCHAR(512)
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_deleteOldBackups] 
	@instanceName		SYSNAME	= NULL
	, @dbname			SYSNAME	= NULL
	, @keepNbackups		TINYINT	= NULL 
	, @includeMockFile	BIT		= 0 
	, @debugging		BIT		= 0 
AS
BEGIN

	SET NOCOUNT ON
	
	DECLARE @databases		TABLE (ID				INT IDENTITY(1,1)
									, dbname		SYSNAME
									, backupPath	NVARCHAR(512)
									, keepNbackups  TINYINT)

	DECLARE @filesToDelete	TABLE (ID			INT IDENTITY
									, fileName	SYSNAME NULL)

	DECLARE @numDBs				INT
			, @countDBs			INT = 1
			, @path				NVARCHAR(512)	-- database's backups path 
			, @dirCmd			NVARCHAR(1000)
			, @delCmd			NVARCHAR(1000)
			, @errorMsg			NVARCHAR(1000)
			, @emailCmd			NVARCHAR(1000)

	DECLARE @countDelete		INT = 1
			, @numDelete		INT	
			, @minIDToDelete	INT	
			, @fileName			SYSNAME
	
	INSERT @databases (dbname, backupPath, keepNbackups)
		SELECT TOP 100 PERCENT
				name
			  , [DBA].dbo.getBackupRootPath(D.server_name, D.name) 
			  , COALESCE(@keepNbackups, D.keepNbackups, I.keepNbackups)
			FROM [DBA].[dbo].[DatabaseInformation] AS D
				INNER JOIN [DBA].[dbo].[ServerConfigurations] AS I  
					ON I.server_name= D.server_name
			WHERE D.server_name = ISNULL(@instanceName, @@SERVERNAME)
				AND D.name = ISNULL(@dbname, D.name)
			ORDER BY name ASC

	SET @numDBs = @@ROWCOUNT

	WHILE @countDBs <= @numDBs BEGIN
	
		SELECT @dbname			= d.dbname 
				, @path			= d.backupPath 
				, @keepNbackups = d.keepNbackups
			FROM @databases AS d
			WHERE d.ID = @countDBs

		BEGIN TRY
		
			-- Once we have the new backups in place, let's check what can be deleted 
			-- Files are ordered by date asc + alphabetically asc (in case backups are distributed in multiple files with exactly same date)
			--SET @dirCmd = 'EXEC master..xp_cmdshell ''dir /B /ODN "' + @path + '*.bak" "' + @path + '*.trn"'''
	
			--PRINT @dirCmd 

			DELETE @filesToDelete

			-- Gets the list of files in the directory sorted by date (oldest first)
			-- We will delete all files till the last FULL BACKUP
			INSERT INTO @filesToDelete (fileName)
			EXEC DBA.dbo.DBA_getBackupFilesList @path
			--sp_executesql @dirCmd
		
			IF EXISTS (SELECT 1 FROM @filesToDelete WHERE fileName = 'Access is denied.') BEGIN 
				SET  @errorMsg = 'The folder "' + @path + '" is not accessible.'
				RAISERROR(@errorMsg, 1, 0, 0) WITH NOWAIT
				SET @countDBs = @countDBs + 1
				CONTINUE
			END

			-- Insert mock file to see good results when executing from dbo.runFullBackup in debugging mode
			INSERT INTO @filesToDelete (fileName)
				SELECT @dbname +  '_MockFile.bak' WHERE @debugging = 1 AND @includeMockFile = 1

			-- Get the ID of the last Full backup to keep, 
			-- that depends on config vble @keepNbackups
			SELECT @minIDToDelete = MinID
				FROM (SELECT fileName
							, MinID
							, ROW_NUMBER() OVER (ORDER BY MinID DESC) AS RowNumber
						FROM ( SELECT SUBSTRING(fileName, 1, LEN(@dbname) + 16) AS fileName, MIN(ID) AS MinID 
								FROM @filesToDelete
								WHERE fileName like '%.bak'					
								GROUP BY SUBSTRING(fileName, 1, LEN(@dbname) + 16)) AS t) AS tt
				WHERE RowNumber = @keepNbackups
			
			-- Remove from the list of files to delete those which are the latest backup
			-- or any transaction log created right after the last full backup (shouldn't be any, though)
			DELETE 
				FROM @filesToDelete 
				WHERE fileName IS NULL 
					-- 	Delete Non backup files (shouldn't be any, only one null)
					OR (fileName NOT LIKE '%.bak' AND fileName NOT LIKE '%.trn' AND fileName NOT LIKE '%.diff') 
					-- Remove from the list of files to delete the old non desired backups
					OR ID >= ISNULL(@minIDToDelete, ID)
			
			SELECT @numDelete		= MAX(ID) -- Keep Max() as ID is IDENTITY COLUMN
					, @countDelete	= MIN(ID) -- To avoid gaps due to previous deletion
				FROM @filesToDelete

			WHILE @countDelete <= @numDelete BEGIN
			-- Delete old .bak and .trn files from the folder
				SET @fileName	= (SELECT fileName FROM @filesToDelete WHERE ID = @countDelete)
				SET @delCmd		= 'EXEC master..xp_cmdshell ''del "' +  @path + @fileName + '"'''
		
				PRINT @delCmd
				IF ISNULL(@debugging, 0) = 0 BEGIN 	
					EXEC sp_executesql @delCmd
				END
		
				-- There can be gaps in the sequence of IDs, so better take the newest MIN()
				SET @countDelete = (SELECT MIN(ID) FROM @filesToDelete WHERE ID > @countDelete)
			END 
	
		END TRY		
		BEGIN CATCH
			SET @emailCmd = 'EXEC msdb..sp_send_dbmail	@profile_name = ''Admin Profile'', 
														@recipients = ''DatabaseAdministrators@rws.com'', 
														@subject = ''Delete old Backups Failed'', 
														@body = ''' + @@SERVERNAME + ', ' + QUOTENAME(@dbname) + ''''
		
			EXEC sp_executesql @emailCmd
		END CATCH
	
		IF @debugging = 1 BEGIN 	
			PRINT @emailCmd
		END
	
		SET @countDBs = @countDBs + 1
	END
END





GO
