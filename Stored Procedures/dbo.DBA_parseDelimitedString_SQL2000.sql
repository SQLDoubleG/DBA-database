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
CREATE PROCEDURE [dbo].[DBA_parseDelimitedString_SQL2000]
	@string			NVARCHAR(4000)
	, @delimiter	NCHAR(1) = ','
AS
BEGIN
	DECLARE @pos	INT
	DECLARE @piece	NVARCHAR(500)

	SET @delimiter = ISNULL(@delimiter, ',')

	CREATE TABLE #r(
		string NVARCHAR(4000)
	)

	IF RIGHT(RTRIM(@string),1) <> @delimiter BEGIN
		SET @string = @string  + @delimiter
	END

	SET @pos =  CHARINDEX(@delimiter , @string)

	WHILE @pos <> 0 BEGIN
	
		SET @piece = LEFT(@string, @pos - 1)

		IF RTRIM(LTRIM(@piece)) <> '' BEGIN
			INSERT INTO #r
				VALUES (RTRIM(LTRIM(@piece)))
		END

		SET @string = STUFF(@string, 1, @pos, '')
		SET @pos	= CHARINDEX(@delimiter, @string)
	END
	SELECT string FROM #r
END




GO
