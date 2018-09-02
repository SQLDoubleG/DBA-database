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
-- Create date: 21/05/2013
-- Description:	Returns a unquoted name 
-- =============================================
CREATE FUNCTION [dbo].[UNQUOTENAME](
	@str	SYSNAME
)
RETURNS SYSNAME
	WITH SCHEMABINDING 
AS
BEGIN
	-- Declare the return variable here
	DECLARE @R SYSNAME

	DECLARE @char NCHAR(1) = '['
	DECLARE @match NCHAR(1) =	CASE 
									WHEN @char = '[' THEN ']' 
									WHEN @char = '"' THEN '"'
								END 
	
	SET @R = REPLACE(REPLACE(@str,@char,''),@match, '')

	RETURN @R

END




GO
