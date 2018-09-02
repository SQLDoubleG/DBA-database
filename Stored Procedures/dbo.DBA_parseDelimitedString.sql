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
-- Create date: 04/06/2014
-- Description:	Returns a list of values from a delimited string
--				
-- Assupmtions:	
--
-- Change Log:	07/05/2014 RAG Created
--				
-- =============================================
CREATE PROCEDURE [dbo].[DBA_parseDelimitedString]
	@string			NVARCHAR(4000)
	, @delimiter	NCHAR(1) = ','
AS
BEGIN
	
	SET NOCOUNT ON 
	
	DECLARE @XML XML = CONVERT(XML, '<root><s>' + REPLACE(@string, @delimiter, '</s><s>') + '</s></root>')

	SELECT LTRIM(RTRIM(T.c.value('.','NVARCHAR(4000)'))) AS [Value]
		FROM @XML.nodes('/root/s') T(c)
		WHERE T.c.value('.','NVARCHAR(4000)') <> ''
END




GO
