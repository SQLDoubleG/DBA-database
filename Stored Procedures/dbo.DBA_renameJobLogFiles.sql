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
-- Create date: 17/09/2013
-- Description:	Rename Log Files for the specified job and place them into a folder with the following pattern
--				[Drive:\Current Path]\Jobs\yyyy\mm\Step-N-StepName_yyyymmdd[_hhmiss].log
-- Usage:
--				Include the following call as the last step of a job
--
--				USE [DBA]
--				GO

--				DECLARE @job_id uniqueidentifier = CONVERT(uniqueidentifier, $(ESCAPE_NONE(JOBID))) -- tokens can only be used within job steps
--				DECLARE @includeTime bit = 1
--				DECLARE @debugging bit = 1

--				EXECUTE [dbo].[DBA_renameJobLogFiles] 
--					@job_id			= @job_id
--					, @includeTime	= @includeTime
--					, @debugging	= @debugging
--				GO
--
--
-- Change Log:	30/03/2016	RAG - Added paramete @includeTime to add _hhmmss to the output filename.
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_renameJobLogFiles]	
	@job_id			UNIQUEIDENTIFIER
	, @includeTime	BIT = 0
	, @debugging	BIT = 0
AS 
BEGIN

	SET NOCOUNT ON

	DECLARE @outputFiles TABLE (ID					INT IDENTITY
								, job_name			SYSNAME
								, step_no			INT
								, step_name			SYSNAME
								, output_file_name	NVARCHAR(200) NOT NULL)

	DECLARE @numFiles			INT
			, @countFiles		INT = 1
			, @job_name			SYSNAME
			, @output_file_name NVARCHAR(200) 
			, @new_path			NVARCHAR(200) 
			, @new_file_name	NVARCHAR(200) 
			, @year				VARCHAR(4) = DATEPART(YEAR,GETDATE())
			, @month			VARCHAR(2) = RIGHT('00' + CONVERT(VARCHAR,DATEPART(MONTH,GETDATE())), 2)
			, @day				VARCHAR(2) = RIGHT('00' + CONVERT(VARCHAR,DATEPART(DAY,GETDATE())), 2)
			, @time				VARCHAR(6) = REPLACE(CONVERT(VARCHAR,GETDATE(), 108), ':', '') 
			, @dirCmd			NVARCHAR(2000)
			, @mvCmd			NVARCHAR(2000)

	INSERT INTO @outputFiles
	SELECT TOP 100 PERCENT 
			j.name
			, js.step_id
			, js.step_name
			, output_file_name 
		FROM msdb.dbo.sysjobs AS j
			INNER JOIN msdb.dbo.sysjobsteps AS js
				ON js.job_id = j.job_id
		WHERE j.job_id = @job_id
			AND output_file_name IS NOT NULL
		ORDER BY js.step_id

	SET @numFiles = @@ROWCOUNT

	WHILE @countFiles <= @numFiles BEGIN 
	
		SELECT @output_file_name = output_file_name
				, @new_file_name = 'Step-' + CONVERT(VARCHAR,step_no) + '-' + step_name
				, @new_path = REPLACE(output_file_name, DBA.dbo.getFileNameFromPath(output_file_name), '') + 'Jobs\' + @year + '\' + @month + '\' + job_name + '\'
				, @job_name = job_name
			FROM @outputFiles
			WHERE ID = @countFiles

		-- Create folder if does not exist
		SET @dirCmd = 'EXEC master..xp_cmdshell ''if not exist "' + @new_path + '". md "' + @new_path + '".'''
		SET @mvCmd	= 'EXEC master..xp_cmdshell ''move "' + @output_file_name + '" "' + @new_path + @new_file_name + '_' +  @year + @month + @day + CASE WHEN @includeTime = 1 THEN '_' + @time ELSE '' END + '.log"'''

	
		PRINT @dirCmd
		PRINT @mvCmd

		IF ISNULL(@debugging, 0) = 0 BEGIN 	
			EXEC sp_executesql @dirCmd
			EXEC sp_executesql @mvCmd
		END

		SET @countFiles += 1
	END 

END





GO
