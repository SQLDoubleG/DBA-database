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
-- Create date: 09/01/2014
-- Description:	Returns the drive from a given Full Path
-- 
-- Parameters:	- @path	-> Complete file path or File name 
-- =============================================
CREATE FUNCTION [dbo].[getDriveFromFullPath](
	@path NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	DECLARE @slashPos	INT		= CASE 
									WHEN CHARINDEX( ':', @path ) > 0 THEN CHARINDEX( ':', @path ) 
									WHEN CHARINDEX( '\', @path ) > 0 THEN CHARINDEX( '\', @path ) 
									ELSE NULL 
								END

	RETURN ( CASE WHEN @slashPos IS NULL THEN '\' ELSE LEFT( @path, @slashPos ) END )

END




GO
