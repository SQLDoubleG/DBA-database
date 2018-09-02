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
-- Author:		Raul Gonzalez @SQLDoubleG
-- Create date: 18/12/2017
-- Description: Formats the output generated  by relog.exe and exists in the following tables.
--					- CounterData
--					- CounterDetails
-- 
-- Usage:
--
-- Change Log:	18/12/2017	RAG	Created
--				24/01/2018	RAG	Created new columns [CounterDate] and [CounterTime] 
--				05/02/2018	RAG	Added independent statement to create the table if provided and not exists
--								Added primary key to the output table
--				19/02/2018	RAG	Added logic to handle new counters that might come in new processed files
--				30/07/2018	RAG	Changed @SQL_new_col to be NVARCHAR(512) as sysname was too short in some cases
--		
-- =============================================
CREATE PROCEDURE [dbo].[DBA_parseRelogOutput]
	@dbname		   sysname
  , @table_name	   sysname
  , @CounterFilter NVARCHAR(256) = NULL
  , @debugging	   BIT			 = NULL
AS BEGIN

	DECLARE @column_list NVARCHAR(MAX);
	DECLARE @pivot_list NVARCHAR(MAX);
	DECLARE @SQL NVARCHAR(MAX);
	DECLARE @RC INT;

	IF DB_ID (@dbname) IS NULL BEGIN
		RAISERROR (N'The database provided does not exist', 16, 1, 1);
		RETURN -100;
	END;

	-- Get the different perfmon counters to be new columns for the output
	SET @SQL = N'USE ' + QUOTENAME (@dbname)
			   + N'             
        IF OBJECT_ID(''dbo.CounterData'') IS NULL OR OBJECT_ID(''dbo.CounterDetails'') IS NULL BEGIN
            RAISERROR (N''The Relog generated tables are not present on this database, please ensure that [dbo].[CounterData], [dbo].[CounterDetails] and [dbo].[DisplayToID] exist'', 16, 1, 1)            
            RETURN
        END 
         
        SET @column_list = (SELECT DISTINCT N'', '' + QUOTENAME(CONCAT([ObjectName], CHAR(92), [CounterName], NULLIF(CONCAT(N'' ('', InstanceName, N'')''),N'' ()'' ))) AS [text()] 
                    FROM [dbo].[CounterDetails] 
                    WHERE [CounterName] LIKE CONCAT(N''%'', @CounterFilter + N''%'')
                    FOR XML PATH(''''))
  
        SET @pivot_list =   (STUFF(@column_list, 1, 2, ''''))';

	EXECUTE @RC = sys.sp_executesql 
		@stmt = @SQL
	  , @params = N'@column_list NVARCHAR(MAX) OUTPUT,@pivot_list NVARCHAR(MAX) OUTPUT, @CounterFilter NVARCHAR(256)'
	  , @column_list = @column_list OUTPUT
	  , @pivot_list = @pivot_list OUTPUT
	  , @CounterFilter = @CounterFilter;

	IF @RC <> 0 BEGIN
		RETURN @RC;
	END;

	-- Create staging table with the data from pivoting relog tables
	SET @SQL = N'USE ' + QUOTENAME (@dbname) + N' 		

	IF OBJECT_ID(''dbo.stg'') IS NOT NULL DROP TABLE dbo.stg;

	SELECT  [ComputerName]
			,[RecordIndex] 
			,CONVERT(DATETIME2(3), LEFT([CounterDateTime], 23)) AS [CounterDateTime]
			,CONVERT(DATE, CONVERT(DATETIME2(0), LEFT([CounterDateTime], 23))) AS [CounterDate]
			,CONVERT(TIME(0), CONVERT(DATETIME2(0), LEFT([CounterDateTime], 23))) AS [CounterTime]
			' + @column_list + N'
		INTO dbo.stg
		FROM (
			SELECT CONCAT(det.[ObjectName], CHAR(92), det.[CounterName], NULLIF(CONCAT('' ('', det.InstanceName, '')''),'' ()'' )) AS PermonCounter
					,RIGHT(det.[MachineName], LEN(det.[MachineName]) -2) AS [ComputerName]
					,dat.[CounterDateTime] AS [CounterDateTime]
					,dat.[CounterValue]
					,dat.[RecordIndex]
				FROM [dbo].[CounterData] AS dat
					LEFT JOIN [dbo].[CounterDetails] AS det
						ON det.CounterID = dat.CounterID
				WHERE det.[CounterName] LIKE CONCAT(''%'', @CounterFilter + ''%'')
			) AS s
		PIVOT(
			SUM([CounterValue])
		FOR [PermonCounter] IN (' + @pivot_list + ' )) AS pvt;'

	-- if we want the output in a table check if we have to create it or add new columns
	IF @table_name IS NOT NULL BEGIN
		SET @SQL += N' 
		IF OBJECT_ID(''' + @table_name + N''') IS NULL BEGIN
			SELECT *
				INTO ' + @table_name + N'
				FROM dbo.stg
				WHERE 1=0;

			ALTER TABLE ' + @table_name
				   + N' ALTER COLUMN [CounterDateTime] DATETIME2(3) NOT NULL 
			ALTER TABLE ' + @table_name
				   + N' ADD CONSTRAINT PK_ PRIMARY KEY ([CounterDateTime])
		END
		ELSE BEGIN
		
			DECLARE @new_col sysname
			DECLARE @SQL_new_col NVARCHAR(512)

			DECLARE cols CURSOR FAST_FORWARD FORWARD_ONLY LOCAL READ_ONLY
			FOR 
				SELECT c.name
					FROM sys.columns AS c
					WHERE c.object_id = OBJECT_ID(''dbo.stg'')
				EXCEPT
				SELECT name	
					FROM sys.columns WHERE OBJECT_ID = OBJECT_ID(''' + @table_name + ''')

			OPEN cols 

			FETCH NEXT FROM cols INTO @new_col
			WHILE @@FETCH_STATUS = 0 BEGIN

				SET @SQL_new_col = ''ALTER TABLE dbo.parsed ADD '' + QUOTENAME(@new_col) + '' FLOAT NULL''

				EXECUTE sp_executesql @stmt = @SQL_new_col

				FETCH NEXT FROM cols INTO @new_col

			END

			CLOSE cols
			DEALLOCATE cols
			
		END
		';
	END;

	-- Now generate the the query with the right values to PIVOT and get the data out 
	SET @SQL += CHAR (13);

	SET @SQL += CASE WHEN @table_name IS NOT NULL THEN
						 N'INSERT INTO ' + @table_name + N'([ComputerName],[RecordIndex],[CounterDateTime],[CounterDate],[CounterTime]' + @column_list + ')'
					ELSE N''
				END
				+ N'        
    SELECT  TOP(2100000000)
			[ComputerName]
			,[RecordIndex] 
            ,CONVERT(DATETIME2(3), LEFT([CounterDateTime], 23)) AS [CounterDateTime]
            ,CONVERT(DATE, CONVERT(DATETIME2(0), LEFT([CounterDateTime], 23))) AS [CounterDate]
			,CONVERT(TIME(0), CONVERT(DATETIME2(0), LEFT([CounterDateTime], 23))) AS [CounterTime]
            '	+ @column_list
				+ N'
        FROM dbo.stg
		ORDER BY [CounterDateTime] ASC
		
	DROP TABLE dbo.stg';

	SELECT CONVERT (XML, '<!--' + @SQL + '-->');

	IF @debugging = 0 BEGIN
		BEGIN TRY
			EXECUTE @RC = sys.sp_executesql @stmt = @SQL
			  , @params = N'@CounterFilter NVARCHAR(256)'
			  , @CounterFilter = @CounterFilter;
		END TRY
		BEGIN CATCH
			SELECT ERROR_NUMBER ()		AS ErrorNumber
				  , ERROR_SEVERITY ()	AS ErrorSeverity
				  , ERROR_STATE ()		AS ErrorState
				  , ERROR_PROCEDURE ()	AS ErrorProcedure
				  , ERROR_LINE ()		AS ErrorLine
				  , ERROR_MESSAGE ()	AS ErrorMessage;
			RETURN -1000
		END CATCH;
	END;

	IF @RC <> 0 BEGIN
		RETURN @RC;
	END;

END;
GO
