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
-- Create date: 30/05/2013
-- Description:	Converts a DATETIMEOFFSET date to GMT
-- =============================================
CREATE FUNCTION [dbo].[GMTdateTime](
	@date DATETIMEOFFSET(0)
)
RETURNS SMALLDATETIME
AS
BEGIN
	-- Declare the return variable here
	DECLARE @R SMALLDATETIME

	SET @R = CONVERT(SMALLDATETIME, @date, 127) -- gmt

	RETURN @R

END





GO
