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
-- Create date: 12/09/2016 
-- Description:	Returns status of CHECKB  
-- 
-- Parameters: 
--				@dbname, will return for a specific database or all of them if NULL 
--				@numdays, number of rows per database 
-- 
-- Change Log:	 
--				13/09/2016	RAG	Added ErrorNumber 
--				12/12/2016	RAG	Added 'command' 
-- 
-- ============================================= 
CREATE PROCEDURE [dbo].[DBA_CHECKDBStatusInfo] 
	@dbname		SYSNAME		= NULL 
	, @numdays	SMALLINT	= 1 
AS 
BEGIN 
 
SELECT t1.[ID] 
      ,[server_name] 
      ,[name] 
      ,[DBCC_datetime] 
      ,[DBCC_duration] 
      ,[isPhysicalOnly] 
      ,[isDataPurity] 
	  ,[command] 
	  ,[ErrorNumber] 
	FROM [DBA].[dbo].[DBCC_History] AS t1 
		CROSS APPLY (SELECT TOP(@numdays) ID AS ID  
						FROM [DBA].[dbo].[DBCC_History] AS t2  
						WHERE t2.server_name = t1.server_name  
							AND t2.name = t1.name 
						ORDER BY t2.DBCC_datetime DESC) AS t2 
	WHERE t2.ID = t1.ID 
		AND name = ISNULL(@dbname, name) 
	ORDER BY name 
 
END 
GO
