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
-- Create date: 22/11/2013
-- Description:	Performs a Mirroring Role Switching action for the specified database or all
--
-- Parameters:
--				@dbname, name of the database to peform the action. If null will perform the action for all database available
--				@action
--					- 1, remove the Witness Server from the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--					- 2, manual failover (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--					- 3, suspend the mirroring session  (EXECUTE FROM EITHER PRINCIPAL OR MIRROR SERVER)
--					- 4, resume the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--					- 5, manual failback (will be the same as the manual failover) (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--					- 6, add Witness Server from the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--					- 99, create the mirroring sessions, execute in SQLCMD mode
--				@witnessName, indicates the name of the witness server when @action = 6, otherwise will be ignored
--				@debugging, will just print out the statements when TRUE
--
-- Change Log:	
--				01/08/2015	RAG	Added @action = 99 to script how to create the mirroring sessions
-- =============================================
CREATE PROCEDURE [dbo].[DBA_mirroringRoleSwitching] 
	@dbname			SYSNAME	= NULL
	, @action		TINYINT = NULL 	
	, @witnessName	SYSNAME = NULL	-- 'TCP://PBSQLWITNESS.rws.com:5022'
	, @debugging	BIT		= 1		-- 
AS
BEGIN
	
	SET NOCOUNT ON

	DECLARE @cmd	NVARCHAR(1000)
	DECLARE @allCmd TABLE (ID INT IDENTITY, cmd NVARCHAR(1000))
	DECLARE @count	INT = 1
			, @num	INT

	DECLARE @cmdHelp NVARCHAR(2000) = N'
--	@dbname, name of the database to peform the action. If null will perform the action for all database available 
--	@action
--		- 1, remove the Witness Server from the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--		- 2, manual failover (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--		- 3, suspend the mirroring session  (EXECUTE FROM EITHER PRINCIPAL OR MIRROR SERVER)
--		- 4, resume the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--		- 5, manual failback (will be the same as the manual failover) (EXECUTE ONLY FROM THE PRINCIPAL SERVER)
--		- 6, add Witness Server from the mirroring session (EXECUTE ONLY FROM THE PRINCIPAL SERVER) 
--		- 99, create the mirroring sessions, execute in SQLCMD mode
--	@witnessName, indicates the name of the witness server when @action = 6, otherwise will be ignored. Eg. ''TCP://PBSQLWITNESS.rws.com:5022''
--	@debugging, will just print out the statements when TRUE

Consider also the posibility that maybe you are not in the right server for the requested database(s)
'
	SET @action = ISNULL(@action, 0)

	IF @action = 0 BEGIN
		SET @cmdHelp = CHAR(10) + N'Please specify valid values for the following parameters: ' + @cmdHelp
		RAISERROR (@cmdHelp, 16, 1, 1)
		RETURN -101
	END
	
	IF @action = 6 AND ISNULL(@witnessName, '') = '' BEGIN
		SET @cmdHelp = CHAR(10) + N'Please specify the name of the Witness Server' + @cmdHelp
		RAISERROR (@cmdHelp, 16, 1, 1)
		RETURN -101
	END


	INSERT @allCmd
		SELECT	TOP 100 
				'USE [master] ' + CHAR(10) + 
				CASE 
					WHEN @action = 1 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET WITNESS OFF'
					WHEN @action = 2 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER FAILOVER'
					WHEN @action = 3 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER SUSPEND'
					WHEN @action = 4 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER RESUME'
					WHEN @action = 5 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER FAILOVER'
					WHEN @action = 6 THEN 'ALTER DATABASE ' + QUOTENAME(name) + ' SET WITNESS = ''' + @witnessName + ''''
					WHEN @action = 99 THEN  ':CONNECT PBSQLSERVER2' + CHAR(10) + 
											'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER = ''TCP://PBSQLSERVER1.rws.com:5022''' + CHAR(10) + 'GO' + CHAR(10) + 		
											':CONNECT PBSQLSERVER1' + CHAR(10) + 
											'ALTER DATABASE ' + QUOTENAME(name) + ' SET PARTNER = ''TCP://PBSQLSERVER2.rws.com:5022''' + CHAR(10) + 
											'ALTER DATABASE ' + QUOTENAME(name) + ' SET SAFETY OFF' + CHAR(10) + 'GO' + CHAR(10) 
				END AS cmd

			FROM sys.databases AS d
				INNER JOIN sys.database_mirroring AS dm
					ON dm.database_id = d.database_id
			WHERE mirroring_state IS NOT NULL 
				AND ( mirroring_role_desc = 'PRINCIPAL' OR @action = 3 )
				AND d.name = ISNULL(@dbname, d.name)
			ORDER BY 1 ASC
	
	SET @num = @@ROWCOUNT

	IF @num = 0 BEGIN
		SET @cmdHelp = CHAR(10) + N'There is no database to perform the requested action, please check the parameters and try again.' 
					+ CHAR(10) + @cmdHelp 
					+ CHAR(10) + N'Please check the returned resultset.'
		
		SELECT d.name AS database_name
				, mirroring_role_desc
				, mirroring_state_desc
				, mirroring_witness_state_desc
			FROM sys.databases AS d
				INNER JOIN sys.database_mirroring AS dm
					ON dm.database_id = d.database_id 
			WHERE mirroring_state IS NOT NULL
				AND d.name = ISNULL(@dbname, d.name)

		RAISERROR (@cmdHelp, 16, 1, 1)
		RETURN -201
	END	

	WHILE @count <= @num BEGIN
		
		SELECT @cmd = cmd 
			FROM @allCmd 
			WHERE ID = @count

		PRINT @cmd

		IF @debugging = 0 BEGIN 
			EXECUTE sp_executesql @cmd
		END
	
		SET @count += 1

	END

END



GO
