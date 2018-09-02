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
-- Description:	Returns useful info about an error
-- =============================================
CREATE PROCEDURE [dbo].[DBA_getErrorInfo]
AS
BEGIN
	
	SET NOCOUNT ON

	SELECT	ERROR_NUMBER() AS ErrorNumber,
			ERROR_SEVERITY() AS ErrorSeverity,
			ERROR_STATE() as ErrorState,
			ERROR_PROCEDURE() as ErrorProcedure,
			ERROR_LINE() as ErrorLine,
			ERROR_MESSAGE() as ErrorMessage
		INTO #r
	
	DECLARE @ErrorNumber		INT
			, @ErrorSeverity	INT
			, @ErrorState		INT
			, @ErrorProcedure	SYSNAME
			, @ErrorLine		INT
			, @ErrorMessage		NVARCHAR(4000)

	SELECT  @ErrorNumber		= ErrorNumber
			, @ErrorSeverity	= ErrorSeverity
			, @ErrorState		= ErrorState
			, @ErrorProcedure	= ErrorProcedure
			, @ErrorLine		= ErrorLine
			, @ErrorMessage		= ErrorMessage
		FROM #r

	PRINT	N'*************************************************************************' + CHAR(10) +
			N'An error has occurred. ' + CHAR(10) +
			N'Please check previous errors and if the problem persists contact your Database administrator.'  + CHAR(10) + CHAR(10) +
			N'The SP ' + @ErrorProcedure + ' returned the following message:' + CHAR(10) + CHAR(10) + @ErrorMessage + CHAR(10) +
			N'*************************************************************************'  + CHAR(10)
END




GO
