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
-- Create date: 07/10/2013
-- Description:	Returns current date formatted to "yyyymmdd_hhmmss"
--
-- Log History:
--				22/05/2017	RAG	Changed the format to be "yyyymmddhhmmss" to make it compatible with log shipping
-- =============================================
CREATE FUNCTION [dbo].[formatTimeToText]()
RETURNS VARCHAR(15)
AS
BEGIN	
	RETURN LEFT(REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(15),GETDATE(),120), '-', ''), ' ', ''), ':', ''),15)
END
GO
