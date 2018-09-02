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
-- Create date: 12/07/2013
-- Description:	Returns the Extension for a given Filename 
-- 
-- Parameters:	- @fileName -> File name 
-- =============================================
CREATE FUNCTION [dbo].[getFileExtensionFromFilename](
	@fileName NVARCHAR(256)
)
RETURNS SYSNAME
AS
BEGIN

	RETURN  RIGHT( @fileName, CHARINDEX( '.', REVERSE(@fileName) ) )

END




GO
