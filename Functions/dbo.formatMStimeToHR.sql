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
-- Create date: 10/07/2013
-- Description:	Returns a MS time (hhmmss) formatted to "d.hh:mm:ss"
-- =============================================
CREATE FUNCTION [dbo].[formatMStimeToHR](
	@duration INT
)
RETURNS VARCHAR(24)
AS
BEGIN
	-- Declare the return variable here
	DECLARE @strDuration VARCHAR(24)
	DECLARE @R			VARCHAR(24)
	DECLARE @pos		INT

	SET @strDuration = RIGHT(REPLICATE('0',24) + CONVERT(VARCHAR(24),@duration), 24)

	SET @R = ISNULL(NULLIF(CONVERT(VARCHAR, CONVERT(INT,SUBSTRING(@strDuration, 1, 20)) / 24 ),0) + '.', '') + 
				--CONVERT(VARCHAR, CONVERT(INT,SUBSTRING(@duration, 1, 20)) / 24 ) + 'd ' + 
				RIGHT('00' + CONVERT(VARCHAR, CONVERT(INT,SUBSTRING(@strDuration, 1, 20)) % 24 ), 2) + ':' + 
				SUBSTRING( @strDuration, 21, 2) + ':' + 
				SUBSTRING( @strDuration, 23, 2)
	
	RETURN ISNULL(@R,'-')

END




GO
