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
-- Create date: 04/09/2013
-- Description:	Cycles the errorlog file for the current instance if bigger than the threshold
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_cycleERRORLOG]
	@ERRORLOG_MaxSize	BIGINT = 25 -- Size in MB 
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @MaxSize BIGINT = @ERRORLOG_MaxSize * (1024 * 1024) -- Filesize in Bytes

	IF OBJECT_ID('tempdb..#err') IS NOT NULL DROP TABLE #err 

	CREATE TABLE #err (Archive INT, [FileDate] SMALLDATETIME, FileSize BIGINT)

	INSERT INTO #err 
		EXECUTE xp_enumerrorlogs

	IF EXISTS ( SELECT * FROM #err WHERE Archive = 0 AND FileSize > @MaxSize ) -- Filesize in Bytes
		EXECUTE sp_cycle_errorlog 
	ELSE 
		PRINT 'The log does not exceed the threshold'

END



GO
