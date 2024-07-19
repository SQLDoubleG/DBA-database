USE [master];
GO
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;
GO
--=============================================
-- Copyright (C) 2023 Raul Gonzalez, @SQLDoubleG
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
-- Create date: 10/07/2023 
-- Description:	Restores one or more databases from a specified folder
--				If only one database needs restoring use the param @fileName to specify the file.
--
-- Assumptions: The name of each database will be read from the backup header, to restore with a different name, 
--					use @execute = 'N' and change the generated script to match your requirements
--				Valued for @dataPath and @logPath:
--					- If paths are not specified (either NULL or ''), original paths will be used
--					- 'default' will use instance default data and log path
--					- custom paths can be used. Eg: 'C:\Backup\'
--
-- Comments:	check for backup files:
--					EXECUTE sys.xp_dirtree 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQL2019\MSSQL\Backup\', 0, 1
-- Log: 
--				10/07/2023	RAG	Created
--				26/03/2024	RAG	Added support for versions from 2012 upwards
-- 
-- ============================================= 

DECLARE @folderPath nvarchar(512)	= 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQL2019\MSSQL\Backup\';
DECLARE @fileName nvarchar(512)		= ''; -- Specify the filename if only one DB needs restoring
DECLARE @replace char(1)			= 'Y';
DECLARE @recovery char(1)			= 'N';
DECLARE @execute char(1)			= 'N'; -- Change to Y to actually restore, otherwise it will only print the statements
DECLARE @changeDbOwner char(1)		= 'N'; -- Change to Y to actually restore, otherwise it will only print the statements
DECLARE @dataPath nvarchar(512)		= NULL; -- use NULL to keep original paths, 'default' to use deafult instance data path or use your custom path
DECLARE @logPath nvarchar(512)		= NULL;	-- use NULL to keep original paths, 'default' to use deafult instance log path or use your custom path

-- ============================================= 
-- Do not modify below this line
--	unless you know what you are doing!!
-- ============================================= 

DECLARE @dbname sysname;
DECLARE @backupPath nvarchar(512);
DECLARE @backupType smallint;
DECLARE @drop_database nvarchar(MAX);
DECLARE @sql nvarchar(MAX);
DECLARE @msg nvarchar(MAX);

DECLARE @ProductMajorVersion int = (SELECT CONVERT(int, SERVERPROPERTY('ProductMajorVersion')));

-- Set @replace to N if not specified
SET @replace	= ISNULL(@replace, 'N');
SET @recovery	= ISNULL(@recovery, 'N');

-- Sanitize paths
SET @dataPath	= NULLIF(@dataPath, '');
SET @logPath	= NULLIF(@logPath, '');
SET @dataPath	= CASE WHEN @dataPath = 'default' THEN CONVERT(nvarchar(512), SERVERPROPERTY('InstanceDefaultDataPath')) ELSE @dataPath END;
SET @logPath	= CASE WHEN @logPath = 'default' THEN CONVERT(nvarchar(512), SERVERPROPERTY('InstanceDefaultLogPath')) ELSE @logPath END;

SET @dataPath	= IIF(RIGHT(@dataPath, 1) = '\', @dataPath, @dataPath + '\');
SET @logPath	= IIF(RIGHT(@logPath, 1) = '\', @logPath, @logPath + '\');

DROP TABLE IF EXISTS #path;
CREATE TABLE #path(
	file_exists bit,
	is_dir bit,
	parent_exists bit
);

-- Validate Data path
IF @dataPath IS NOT NULL
BEGIN
	TRUNCATE TABLE #path;

	INSERT #path (file_exists, is_dir, parent_exists)
	EXEC xp_fileexist @dataPath;

	IF NOT EXISTS (SELECT * FROM #path WHERE is_dir = 1) AND @execute = 'Y'
	BEGIN
		SET @msg = 'The value specified for the parameter @dataPath is not a valid directory' 
					+ CHAR(10) + 'The process cannot continue, please specify @execute = ''N'' to script the commands';
		RAISERROR (@msg, 16, 1) WITH NOWAIT;
		RETURN;
	END;
END

-- Validate Log path
IF @logPath IS NOT NULL
BEGIN
	TRUNCATE TABLE #path;

	INSERT #path (file_exists, is_dir, parent_exists)
	EXEC xp_fileexist @logPath;

	IF NOT EXISTS (SELECT * FROM #path WHERE is_dir = 1) AND @execute = 'Y'
	BEGIN
		SET @msg = 'The value specified for the parameter @logPath is not a valid directory' 
					+ CHAR(10) + 'The process cannot continue, please specify @execute = ''N'' to script the commands';
		RAISERROR (@msg, 16, 1) WITH NOWAIT;
		RETURN;
	END;
END

-- Validate params
IF @replace NOT IN ('Y', 'N') 
BEGIN
	SET @msg = 'Please specify valid value for @replace, either ''Y'' or ''N''';
	RAISERROR (@msg, 16, 1, 1);
	RETURN;
END;

IF @recovery NOT IN ('Y', 'N') 
BEGIN
	SET @msg = 'Please specify valid value for @recovery, either ''Y'' or ''N''';
	RAISERROR (@msg, 16, 1, 1);
	RETURN;
END;

DROP TABLE IF EXISTS #backupList;
DROP TABLE IF EXISTS #backupHeader;
DROP TABLE IF EXISTS #filelistonly;
DROP TABLE IF EXISTS #fileexist;

CREATE TABLE #backupList (
	subdirectory nvarchar(1000),
	depth int,
	[file] int
);

CREATE TABLE #backupHeader (
	[BackupName] nvarchar(128),
	[BackupDescription] nvarchar(255),
	[BackupType] tinyint,
	[ExpirationDate] datetime,
	[Compressed] tinyint,
	[Position] smallint,
	[DeviceType] tinyint,
	[UserName] nvarchar(128),
	[ServerName] nvarchar(128),
	[DatabaseName] nvarchar(128),
	[DatabaseVersion] int,
	[DatabaseCreationDate] datetime,
	[BackupSize] bigint,
	[FirstLSN] decimal(25, 0),
	[LastLSN] decimal(25, 0),
	[CheckpointLSN] decimal(25, 0),
	[DatabaseBackupLSN] decimal(25, 0),
	[BackupStartDate] datetime,
	[BackupFinishDate] datetime,
	[SortOrder] smallint,
	[CodePage] smallint,
	[UnicodeLocaleId] int,
	[UnicodeComparisonStyle] int,
	[CompatibilityLevel] tinyint,
	[SoftwareVendorId] int,
	[SoftwareVersionMajor] int,
	[SoftwareVersionMinor] int,
	[SoftwareVersionBuild] int,
	[MachineName] nvarchar(128),
	[Flags] int,
	[BindingID] uniqueidentifier,
	[RecoveryForkID] uniqueidentifier,
	[Collation] nvarchar(128),
	[FamilyGUID] uniqueidentifier,
	[HasBulkLoggedData] bit,
	[IsSnapshot] bit,
	[IsReadOnly] bit,
	[IsSingleUser] bit,
	[HasBackupChecksums] bit,
	[IsDamaged] bit,
	[BeginsLogChain] bit,
	[HasIncompleteMetaData] bit,
	[IsForceOffline] bit,
	[IsCopyOnly] bit,
	[FirstRecoveryForkID] uniqueidentifier,
	[ForkPointLSN] decimal(25, 0),
	[RecoveryModel] nvarchar(60),
	[DifferentialBaseLSN] decimal(25, 0),
	[DifferentialBaseGUID] uniqueidentifier,
	[BackupTypeDescription] nvarchar(128),
	[BackupSetGUID] uniqueidentifier,
	[CompressedBackupSize] bigint
);

-- More columns were added to newer versions
-- SQL 2012
IF @ProductMajorVersion >= 11 
BEGIN
	ALTER TABLE #backupHeader ADD [Containment] tinyint;
END

-- SQL 2014
IF @ProductMajorVersion >= 12
BEGIN
	ALTER TABLE #backupHeader ADD [KeyAlgorithm] nvarchar(32);
	ALTER TABLE #backupHeader ADD [EncryptorThumbprint] varbinary(20);
	ALTER TABLE #backupHeader ADD [EncryptorType] nvarchar(32);
END

-- SQL 2022
IF @ProductMajorVersion >= 16
BEGIN
	ALTER TABLE #backupHeader ADD LastValidRestoreTime datetime;
	ALTER TABLE #backupHeader ADD TimeZone nvarchar(32);
	ALTER TABLE #backupHeader ADD CompressionAlgorithm nvarchar(32);
END

CREATE TABLE #filelistonly (
	[LogicalName] nvarchar(128),
	[PhysicalName] nvarchar(260),
	[Type] nchar(1),
	[FileGroupName] nvarchar(128),
	[Size] bigint,
	[MaxSize] bigint,
	[FileId] bigint,
	[CreateLSN] decimal(25, 0),
	[DropLSN] decimal(25, 0),
	[UniqueId] uniqueidentifier,
	[ReadOnlyLSN] decimal(25, 0),
	[ReadWriteLSN] decimal(25, 0),
	[BackupSizeInBytes] bigint,
	[SourceBlockSize] int,
	[FileGroupId] int,
	[LogGroupGUID] uniqueidentifier,
	[DifferentialBaseLSN] decimal(25, 0),
	[DifferentialBaseGUID] uniqueidentifier,
	[IsReadOnly] bit,
	[IsPresent] bit,
	[TDEThumbprint] varbinary(20),
	[SnapshotUrl] nvarchar(336)
);

CREATE TABLE #fileexist (
	[FileExists] bit,
	[IsDirectory] bit,
	[ParentDirectoryExists] bit
);

INSERT INTO #backupList (subdirectory, depth, [file])
EXECUTE sys.xp_dirtree @folderPath , 0, 1;

DECLARE c CURSOR LOCAL STATIC READ_ONLY 
FOR SELECT subdirectory FROM #backupList
	WHERE (ISNULL(@fileName, '') = ''
			OR subdirectory = @fileName);

OPEN c;
FETCH NEXT FROM c INTO @backupPath;

WHILE @@FETCH_STATUS = 0 
BEGIN

	TRUNCATE TABLE #backupHeader;
	TRUNCATE TABLE #filelistonly;
	TRUNCATE TABLE #fileexist;

	SET @drop_database = NULL;

	SET @sql = 'RESTORE HEADERONLY FROM DISK = ''[backupPath]''';
	SET @sql = REPLACE(@sql, '[backupPath]', @folderPath + @backupPath);

	BEGIN TRY
	INSERT INTO #backupHeader -- column list is variable depending on the version, hence not specified
	EXECUTE sys.sp_executesql @stmt = @sql;
	END TRY
	BEGIN CATCH
		PRINT 'File ' + @folderPath + @backupPath + ' is not a valid SQL backup file';
		FETCH NEXT FROM c INTO @backupPath;
		CONTINUE;
	END CATCH;

/*
Backup type:
1 = Database
2 = Transaction log
4 = File
5 = Differential database
6 = Differential file
7 = Partial
8 = Differential partial
*/

	SELECT @dbname = [DatabaseName], 
			@backupType = BackupType
	FROM #backupHeader;

	IF DB_ID(@dbname) IS NOT NULL AND @backupType = 1
	-- Database exists
	BEGIN
		IF @replace = 'Y'
		-- We want to replace
		BEGIN
			SET @drop_database = 'ALTER DATABASE [?] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10) + 'DROP DATABASE [?];';
			SET @drop_database = REPLACE(@drop_database, '?', @dbname);
		END;
		ELSE
		-- Database exists but we don't want to replace it, ERROR
		BEGIN
			SET @msg = REPLACE('The database [?] already exists, please specify @replace = ''Y'' if you want to overwrite', '?', @dbname); 
			RAISERROR (@msg, 16, 1, 1);
			RETURN;
		END;
	END;

	-- Get files to generate RESTORE command later
	SET @sql = 'RESTORE FILELISTONLY FROM DISK = ''[backupPath]''';
	SET @sql = REPLACE(@sql, '[backupPath]', @folderPath + @backupPath);

	-- Get the list of files
	INSERT INTO #filelistonly (
		[LogicalName],
		[PhysicalName],
		[Type],
		[FileGroupName],
		[Size],
		[MaxSize],
		[FileId],
		[CreateLSN],
		[DropLSN],
		[UniqueId],
		[ReadOnlyLSN],
		[ReadWriteLSN],
		[BackupSizeInBytes],
		[SourceBlockSize],
		[FileGroupId],
		[LogGroupGUID],
		[DifferentialBaseLSN],
		[DifferentialBaseGUID],
		[IsReadOnly],
		[IsPresent],
		[TDEThumbprint],
		[SnapshotUrl]
	)
	EXECUTE sys.sp_executesql @stmt = @sql;

	-- Correct the paths to the target ones
	IF @dataPath IS NOT NULL 
	BEGIN
		UPDATE #filelistonly
			SET PhysicalName = @dataPath + RIGHT(PhysicalName, CHARINDEX('\', REVERSE(PhysicalName))-1)
		WHERE Type IN ('D', 'S');
	END;

	IF @logPath IS NOT NULL 
	BEGIN
		UPDATE #filelistonly
			SET PhysicalName = @logPath + RIGHT(PhysicalName, CHARINDEX('\', REVERSE(PhysicalName))-1)
		WHERE Type NOT IN ('D', 'S');
	END;

	-- Generate RESTORE DATABASE command
	SET @sql = N'RESTORE DATABASE [dbname]
	FROM DISK = ''[backupPath]''
	WITH STATS';

	SET @sql += ', ' + CASE WHEN @recovery = 'N' THEN 'NO' ELSE '' END + 'RECOVERY';

	-- For full backups MOVE files to the correct location
	IF @backupType = 1
	BEGIN
	-- Paths have been corrected already
		SET @sql += (SELECT CHAR(10) + ', MOVE ''' + LogicalName +  '''	TO ''' + PhysicalName + ''''
						FROM #filelistonly AS r
						FOR XML PATH('')) + ';';
	END;

	IF @changeDbOwner = 'Y'
	BEGIN
		-- Change db_owner to [sa]
		SET @sql += CHAR(10) + CHAR(13) + 'ALTER AUTHORIZATION ON DATABASE::[dbname] TO [sa]';

	END;

	SET @sql = REPLACE(@sql, '[dbname]', QUOTENAME(@dbname));
	SET @sql = REPLACE(@sql, '[backupPath]', @folderPath + @backupPath);

	PRINT @drop_database;
	PRINT @sql;

	IF @execute = 'Y' 
	BEGIN
		EXECUTE sys.sp_executesql @stmt = @drop_database;
		EXECUTE sys.sp_executesql @stmt = @sql;
	END;

	FETCH NEXT FROM c INTO @backupPath;

END;

CLOSE c;
DEALLOCATE c;