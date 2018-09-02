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
-- Create date: 04/10/2013
-- Description:	Returns default paths for the current instance. Data, Log, Backup
--				If a different instance is passed as parameter it will return no values, this behaviour is correct
--				as this function is called by the fuction [dbo].[getBackupRootPath] for ANY instance, so returning 
--				the default paths for the current might be wrong in some cases
--
-- Log History:	19/12/2013 - Modify the output table which now returns 
--					[InstallRootDirectory]		- Path of SQL Server Installation
--					[InstallSharedDirectory]	- Path of SQL Server Shared Features Installation
--					[ErrorlogPath]				- Path of ERRORLOG files
--					[MasterDBPath]				- Path of Master database data file
--					[MasterDBLogPath]			- Path of Master database log file
--					[DefaultFile]				- Default path for data files for new databases
--					[DefaultLog]				- Default path for log files for new databases
--					[FilestreamShareName]		- FileStream Share name
--					[BackupDirectory]			- Default path for database backups
--
-- 
-- Examples:
--				SELECT * FROM [dbo].[getInstanceDefaultPaths](@@SERVERNAME)
-- =============================================
CREATE FUNCTION [dbo].[getInstanceDefaultPaths] (
	@instanceName SYSNAME
)
RETURNS @SmoDefaults 
	TABLE ( [InstallRootDirectory]		NVARCHAR(512)
			, [InstallSharedDirectory]	NVARCHAR(512)
			, [ErrorlogPath]			NVARCHAR(512)
			, [MasterDBPath]			NVARCHAR(512)
			, [MasterDBLogPath]			NVARCHAR(512)
			, [DefaultFile]				NVARCHAR(512)
			, [DefaultLog]				NVARCHAR(512)
			, [FilestreamShareName]		NVARCHAR(512)
			, [BackupDirectory]			NVARCHAR(512))
AS
BEGIN
	
	DECLARE @InstallRootDirectory		NVARCHAR(512)
			, @InstallSharedDirectory	NVARCHAR(512)
			, @ErrorlogPath				NVARCHAR(512)
			, @MasterDBPath				NVARCHAR(512)
			, @MasterDBLogPath			NVARCHAR(512)
			, @DefaultFile				NVARCHAR(512)
			, @DefaultLog				NVARCHAR(512)
			, @FilestreamShareName		NVARCHAR(512)
			, @BackupDirectory			NVARCHAR(512)

	DECLARE @Arg						SYSNAME
			, @Param					SYSNAME = 'dummy'
			, @n						INT = 0
			
	DECLARE @HkeyLocal					NVARCHAR(18)
			, @MSSqlServerRegPath		NVARCHAR(31)
			, @InstanceRegPath			SYSNAME
			, @SetupRegPath				SYSNAME
			, @RegPathParams			SYSNAME
			, @FilestreamRegPath		SYSNAME

	SET @HkeyLocal			= N'HKEY_LOCAL_MACHINE'
	SET @MSSqlServerRegPath	= N'SOFTWARE\Microsoft\MSSQLServer'
	SET @InstanceRegPath	= @MSSqlServerRegPath	+ N'\MSSQLServer'
	SET @FilestreamRegPath	= @InstanceRegPath		+ N'\Filestream'
	SET @SetupRegPath		= @MSSqlServerRegPath	+ N'\Setup'
	SET @RegPathParams		= @InstanceRegPath		+ N'\Parameters'


	WHILE(@Param IS NOT NULL) BEGIN
		SELECT @Param = NULL
		SELECT @Arg = 'SqlArg' + CONVERT(NVARCHAR,@n)
		
		EXEC master.dbo.xp_instance_regread @HkeyLocal, @RegPathParams, @Arg, @Param OUTPUT

		IF @Param like '-d%' BEGIN
			SELECT @Param			= SUBSTRING(@Param, 3, 255)
			SELECT @MasterDBPath	= SUBSTRING(@Param, 1, LEN(@Param) - CHARINDEX('\', REVERSE(@Param)))
		END
		ELSE IF @Param like '-l%' BEGIN
			SELECT @Param			= SUBSTRING(@Param, 3, 255)
			SELECT @MasterDBLogPath	= SUBSTRING(@Param, 1, LEN(@Param) - CHARINDEX('\', REVERSE(@Param)))
		END
		ELSE IF @Param like '-e%' BEGIN
			SELECT @Param			= SUBSTRING(@Param, 3, 255)
			SELECT @ErrorlogPath	= SUBSTRING(@Param, 1, LEN(@Param) - CHARINDEX('\', REVERSE(@Param)))
		END

		SELECT @n = @n+1
	END

	IF dbo.[getNumericSQLVersion](CONVERT(SYSNAME, SERVERPROPERTY('ProductVersion'))) >= 11 BEGIN
		SET @DefaultFile	= CONVERT(NVARCHAR(512), (SELECT SERVERPROPERTY('InstanceDefaultDataPath')) )
		SET @DefaultLog		= CONVERT(NVARCHAR(512), (SELECT SERVERPROPERTY('InstanceDefaultLogPath')) )
	END
	ELSE BEGIN
		EXEC master.dbo.xp_instance_regread @HkeyLocal, @InstanceRegPath, N'DefaultData',	@DefaultFile			OUTPUT
		EXEC master.dbo.xp_instance_regread @HkeyLocal, @InstanceRegPath, N'DefaultLog',	@DefaultLog				OUTPUT
	END 

    EXEC master.dbo.xp_instance_regread @HkeyLocal, @InstanceRegPath,	N'BackupDirectory', @BackupDirectory		OUTPUT    
	EXEC master.dbo.xp_instance_regread @HkeyLocal, @FilestreamRegPath, N'ShareName',		@FilestreamShareName	OUTPUT
	EXEC master.dbo.xp_instance_regread @HkeyLocal, @SetupRegPath,		N'SQLPath',			@InstallRootDirectory	OUTPUT
	EXEC master.dbo.xp_instance_regread @HkeyLocal, @SetupRegPath,		N'SQLPath',			@InstallSharedDirectory OUTPUT

	INSERT @SmoDefaults
		SELECT CASE WHEN RIGHT(@InstallRootDirectory , 1)		= '\' THEN @InstallRootDirectory	ELSE @InstallRootDirectory		+ '\' END
				, CASE WHEN RIGHT(@InstallSharedDirectory , 1)	= '\' THEN @InstallSharedDirectory	ELSE @InstallSharedDirectory	+ '\' END
				, CASE WHEN RIGHT(@ErrorlogPath , 1)			= '\' THEN @ErrorlogPath			ELSE @ErrorlogPath				+ '\' END
				, CASE WHEN RIGHT(@MasterDBPath , 1)			= '\' THEN @MasterDBPath			ELSE @MasterDBPath				+ '\' END
				, CASE WHEN RIGHT(@MasterDBLogPath , 1)			= '\' THEN @MasterDBLogPath			ELSE @MasterDBLogPath			+ '\' END
				, CASE WHEN RIGHT(@DefaultFile , 1)				= '\' THEN @DefaultFile				ELSE @DefaultFile				+ '\' END
				, CASE WHEN RIGHT(@DefaultLog , 1)				= '\' THEN @DefaultLog				ELSE @DefaultLog				+ '\' END
				, @FilestreamShareName
				, CASE WHEN RIGHT(@BackupDirectory , 1)			= '\' THEN @BackupDirectory			ELSE @BackupDirectory			+ '\' END
		WHERE @instanceName = @@SERVERNAME

	RETURN
END



GO
