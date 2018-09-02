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
-- Author:		Gareth Lyons
-- Create date: 18/07/2012
-- Description:	Shrinks Log Files. Can be run manually, scheduled, or in response to an alert.
-- ChangeLog:	
--				04/03/2013 GPL 
--					Rewritten to use sys.master_files catalog view instead of looping through databases to read sys.database_files.
--					Files sizes converted to MB avoid INT overflows.
--				RAG Created in DBA database and added parameter @debugging
-- =============================================
CREATE PROCEDURE [dbo].[DBA_shrinkLogFiles]
		@LogSizeMB				BIGINT 
		, @LogSpaceUsedPercent	TINYINT
		, @LogMinSizeMB			BIGINT
		, @debugging			BIT = 0

AS
BEGIN

	SET NOCOUNT ON

	--DECLARE @LogSizeMB INT = 20480,
	--		@LogSpaceUsedPercent TINYINT = 50,
	--		@LogMinSizeMB INT = 10240

	DECLARE @dblist TABLE (id INT IDENTITY(1,1), databasename NVARCHAR(255), logsize FLOAT, dbsize BIGINT, logfilename NVARCHAR(255), 
							targetsize AS CAST(CASE WHEN logsize*0.5 > dbsize*0.2 THEN dbsize*0.2 ELSE logsize*0.5 END AS BIGINT)
							)
							
	DECLARE @pos		INT = 1,
			@maxid		INT,
			@dbname		NVARCHAR(255) = '',
			@sqlstring	NVARCHAR(2000) = '',
			@logname	NVARCHAR(255),
			@targetsize NVARCHAR(128)


		INSERT INTO @dblist (databasename, logsize, dbsize, logfilename)
			SELECT	DB_NAME(mfl.database_id) AS databasename, 
					mfl.size/128 AS logsize, 
					(SELECT SUM(mfd.size/128) FROM sys.master_files mfd WHERE mfl.database_id = mfd.database_id AND mfd.[type] = 0) AS dbsize, 
					mfl.name AS logfilename--, 
					--logsize.cntr_value/1024 AS TotalLogSizeMB, 
					--logused.cntr_value AS PercentUsed
				FROM master.sys.databases d
					INNER JOIN master.sys.master_files mfl 
						ON mfl.database_id = d.database_id
					LEFT JOIN sys.dm_os_performance_counters logsize 
						ON logsize.counter_name = 'Log File(s) Size (KB)' 
							AND logsize.instance_name = d.name
					LEFT JOIN sys.dm_os_performance_counters logused 
						ON logused.counter_name = 'Percent Log Used' 
							AND logused.instance_name = d.name
				WHERE d.name NOT IN ('master', 'msdb', 'tempdb', 'model')
					AND d.[state] = 0 --Online
					AND mfl.[type] = 1 -- LogFiles
					AND logsize.cntr_value/1024 > @LogSizeMB
					AND logused.cntr_value < @LogSpaceUsedPercent

	SELECT	@maxid = (select MAX(id) from @dblist),
			@dbname = '',
			@sqlstring = ''

--SELECT *, @LogMinSizeMB FROM @dblist

	WHILE @pos <= @maxid
		BEGIN

			SET @dbname		= (SELECT databasename FROM @dblist WHERE id = @pos)
			SET @logname	= (SELECT logfilename FROM @dblist WHERE id = @pos)
			SET @targetsize = CAST((SELECT CASE WHEN targetsize < @LogMinSizeMB THEN @LogMinSizeMB ELSE targetsize END FROM @dblist WHERE id = @pos) AS NVARCHAR(128))

			SET @sqlstring	= N'USE [' + @dbname + N'] DBCC SHRINKFILE(''' + @logname + N''', ' + @targetsize + N')'

			PRINT @sqlstring

			IF ISNULL(@debugging, 0) = 0 BEGIN
				BEGIN TRY
					EXEC sp_executesql @sqlstring
				END TRY
				BEGIN CATCH
					PRINT 'There was an error:' + CHAR(10) + ERROR_MESSAGE()
				END CATCH
			END 
			
			SET @pos = @pos + 1

		END
END




GO
