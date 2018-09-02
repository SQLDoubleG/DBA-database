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
-- Create date: 27/10/2014
-- Description:	Returns header and label information from a backup file
--
-- Parameters:	- @FilePath						-> Full path of the backup file
--				- @BackupType			OUTPUT	->	1 = Database
--													2 = Transaction log
--													4 = File
--													5 = Differential database
--													6 = Differential file
--													7 = Partial
--													8 = Differential partial
--				- @BackupDatabaseName	OUTPUT	-> Name of the database that was backed up
--				- @IsCopyOnly			OUTPUT	-> A copy-only backup does not impact the overall backup and restore procedures for the database.
--				- @MediaSetId			OUTPUT	-> Unique identification number of the media set
--				- @FamilyCount			OUTPUT	-> Number of media families in the media set
--				- @FamilySequenceNumber	OUTPUT	-> Sequence number of this family
--
-- Log History:	
--
--				09/01/2016	RAG	- Added New columns from SQL 2014 SP1 from RESTORE HEADERONLY command
--								- Add columns depending on SQL version instead of create different tables, that simplifies the logic as the final query use always the same table
-- =============================================
CREATE PROCEDURE [dbo].[DBA_getBackupFileInformation]
	@FilePath				NVARCHAR(256)
	, @BackupType			SMALLINT			OUTPUT
	, @BackupDatabaseName	NVARCHAR(128)		OUTPUT
	, @IsCopyOnly			BIT					OUTPUT
	, @MediaSetId			UNIQUEIDENTIFIER	OUTPUT
	, @FamilyCount			INT					OUTPUT
	, @FamilySequenceNumber	INT					OUTPUT
AS
BEGIN

	SET NOCOUNT ON

	IF OBJECT_ID('tempdb..#BackupLabel')	IS NOT NULL DROP TABLE #BackupLabel
	IF OBJECT_ID('tempdb..#BackupHeader')	IS NOT NULL DROP TABLE #BackupHeader

	DECLARE @SQLServerNumericVersion	INT = DBA.dbo.getNumericSQLVersion(NULL)

	-- Stores results from RESTORE LABELONLY
	CREATE TABLE #BackupLabel
			( MediaName				NVARCHAR(128)		NULL
			, MediaSetId			UNIQUEIDENTIFIER
			, FamilyCount			INT
			, FamilySequenceNumber	INT
			, MediaFamilyId			UNIQUEIDENTIFIER
			, MediaSequenceNumber	INT
			, MediaLabelPresent		TINYINT
			, MediaDescription		NVARCHAR(255)		NULL
			, SoftwareName			NVARCHAR(128)
			, SoftwareVendorId		INT
			, MediaDate				DATETIME
			, Mirror_Count			INT
			, IsCompressed			BIT)

	-- Stores results from RESTORE HEADERONLY
	CREATE TABLE #BackupHeader 
			( BackupName			NVARCHAR(128)		NULL
			, BackupDescription		NVARCHAR(255)		NULL
			, BackupType			SMALLINT			NULL
			, ExpirationDate		DATETIME			NULL
			, Compressed			BIT					NULL
			, Position				SMALLINT			NULL
			, DeviceType			TINYINT				NULL
			, UserName				NVARCHAR(128)		NULL
			, ServerName			NVARCHAR(128)		NULL
			, DatabaseName			NVARCHAR(128)		NULL
			, DatabaseVersion		INT					NULL
			, DatabaseCreationDate	DATETIME			NULL
			, BackupSize			NUMERIC(20,0)		NULL
			, FirstLSN				NUMERIC(25,0)		NULL
			, LastLSN				NUMERIC(25,0)		NULL
			, CheckpointLSN			NUMERIC(25,0)		NULL
			, DatabaseBackupLSN		NUMERIC(25,0)		NULL
			, BackupStartDate		DATETIME			NULL
			, BackupFinishDate		DATETIME			NULL
			, SortOrder				SMALLINT			NULL
			, CodePage				SMALLINT			NULL
			, UnicodeLocaleId		INT					NULL
			, UnicodeComparisonStyle INT				NULL
			, CompatibilityLevel	TINYINT				NULL
			, SoftwareVendorId		INT					NULL
			, SoftwareVersionMajor	INT					NULL
			, SoftwareVersionMinor	INT					NULL
			, SoftwareVersionBuild	INT					NULL
			, MachineName			NVARCHAR(128)		NULL
			, Flags					INT					NULL
			, BindingID				UNIQUEIDENTIFIER	NULL
			, RecoveryForkID		UNIQUEIDENTIFIER	NULL
			, Collation				NVARCHAR(128)		NULL
			, FamilyGUID			UNIQUEIDENTIFIER	NULL
			, HasBulkLoggedData		BIT					NULL
			, IsSnapshot			BIT					NULL
			, IsReadOnly			BIT					NULL
			, IsSingleUser			BIT					NULL
			, HasBackupChecksums	BIT					NULL
			, IsDamaged				BIT					NULL
			, BeginsLogChain		BIT					NULL
			, HasIncompleteMetaData	BIT					NULL
			, IsForceOffline		BIT					NULL
			, IsCopyOnly			BIT					NULL
			, FirstRecoveryForkID	UNIQUEIDENTIFIER	NULL
			, ForkPointLSN			NUMERIC(25,0)		NULL
			, RecoveryModel			NVARCHAR(60)		NULL
			, DifferentialBaseLSN	NUMERIC(25,0)		NULL
			, DifferentialBaseGUID	UNIQUEIDENTIFIER	NULL
			, BackupTypeDescription	NVARCHAR(60)		NULL
			, BackupSetGUID			UNIQUEIDENTIFIER	NULL
			, CompressedBackupSize	BIGINT				NULL)
	
	IF @SQLServerNumericVersion >= 11 BEGIN
		ALTER TABLE #BackupHeader ADD containment			TINYINT	-- NEW FOR SQL2012 onwards
	END 

	IF CONVERT(VARCHAR, SERVERPROPERTY('ResourceVersion')) >= '12.00.4100' BEGIN 
		ALTER TABLE #BackupHeader ADD KeyAlgorithm			NVARCHAR(32)	NULL	-- NEW FOR SQL2014 SP1 onwards
		ALTER TABLE #BackupHeader ADD EncryptorThumbprint	VARBINARY(20)	NULL	-- NEW FOR SQL2014 SP1 onwards
		ALTER TABLE #BackupHeader ADD EncryptorType			NVARCHAR(32)	NULL	-- NEW FOR SQL2014 SP1 onwards
 	END 

	DECLARE @ErrorMsg					NVARCHAR(1000)	= N''
			, @RestoreLabelCommand		NVARCHAR(512)	= N'INSERT INTO #BackupLabel' + CHAR(10) + 
																N'EXEC sp_executesql N''RESTORE LABELONLY FROM DISK = ''''' + @FilePath + ''''''''
			, @RestoreHeaderCommand		NVARCHAR(512)	= N'INSERT INTO #BackupHeader' + CHAR(10) + 
																N'EXEC sp_executesql N''RESTORE HEADERONLY FROM DISK = '''''+ @FilePath + ''''''''
	BEGIN TRY
		
		--PRINT @RestoreLabelCommand
		--PRINT @RestoreHeaderCommand
		EXEC sp_executesql @RestoreLabelCommand
		EXEC sp_executesql @RestoreHeaderCommand

		SELECT @BackupType				= h.BackupType  
				, @BackupDatabaseName	= h.DatabaseName
				, @IsCopyOnly			= h.IsCopyOnly  
				, @MediaSetId			= l.MediaSetId
				, @FamilyCount			= l.FamilyCount
				, @FamilySequenceNumber		= l.FamilySequenceNumber
			FROM #BackupLabel AS l
				OUTER APPLY( SELECT DatabaseName, BackupType, IsCopyOnly FROM #BackupHeader AS h) AS h
	END TRY
	BEGIN CATCH
		SET @ErrorMsg = ERROR_MESSAGE()
		RAISERROR ( @ErrorMsg, 16,1 ) WITH NOWAIT
		RETURN -5000
	END CATCH
END





GO
