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
-- Create date: 17/02/2015
-- Description:	Returns list of days which match the bit value in [DBA].[dbo].[DaysOfWeekBitWise]
--
-- Log History:	
-- 
-- Examples:
--				SELECT * FROM [DBA].[dbo].[getDayNamesList] (127)
-- =============================================
CREATE FUNCTION [dbo].[getDayNamesList] (
	@bitValue INT
)
RETURNS TABLE
AS
RETURN( 
	SELECT ISNULL( STUFF( (SELECT N', ' + B.name 
		FROM DBA.dbo.DaysOfWeekBitWise AS B 
		WHERE B.bitValue & @bitValue = B.bitValue 
		FOR XML PATH('') ), 1, 2, '' ), 'None' ) AS DayList
)





GO
