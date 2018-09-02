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
-- Create date: 20/12/2013
-- Description:	Returns the space used in MB for a given n_bytes in a given n_rows
--
-- Parameters:	- @n_rows	
--				- @n_bytes	
-- Examples:
--				SELECT [dbo].[getSpaceUsed] (442291782, 4)
--
-- Change Log:	
--
-- =============================================
CREATE FUNCTION [dbo].[getSpaceUsed](
	@n_rows		INT
	, @n_bytes	INT
)
RETURNS DECIMAL(10,2)
AS
BEGIN

	DECLARE @r DECIMAL(10,2)

	SELECT @r = (@n_rows * @n_bytes) / 1024. / 1024

	RETURN @r

END






GO
