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
-- Create date: 2014-03-04
-- Description:	Function to return numeric SQL Version
-- =============================================
CREATE FUNCTION [dbo].[getNumericSQLVersion](
	@ProductVersion NVARCHAR(128)
)
	RETURNS DECIMAL(3,1)
AS
BEGIN

	DECLARE @version NVARCHAR(128) = ISNULL(@ProductVersion, CONVERT(NVARCHAR(128),SERVERPROPERTY('ProductVersion')))
	
	RETURN CONVERT(DECIMAL(3,1), (LEFT( @version,  CHARINDEX('.', @version, 0) + 1 )) )

END




GO
