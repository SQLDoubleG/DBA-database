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
-- Create date: 25/06/2013
-- Description:	Function to return SQL Version (e.g. 2005, 2008 R2) from Version Number (e.g. 9.0, 10.5)
-- =============================================
CREATE FUNCTION [dbo].[fn_SQLVersion](	
	@ProductVersion NVARCHAR(128)
)

RETURNS NVARCHAR(50)
AS
BEGIN

DECLARE @Result NVARCHAR(50)

SELECT @Result = CASE 
		WHEN @ProductVersion LIKE '14.%' THEN 'SQL Server 2017'
		WHEN @ProductVersion LIKE '13.%' THEN 'SQL Server 2016'
		WHEN @ProductVersion LIKE '12.%' THEN 'SQL Server 2014'
		WHEN @ProductVersion LIKE '11.%' THEN 'SQL Server 2012'
		WHEN @ProductVersion LIKE '10.5%' THEN 'SQL Server 2008 R2'
		WHEN @ProductVersion LIKE '10.%' THEN 'SQL Server 2008'
		WHEN @ProductVersion LIKE '9.%' THEN 'SQL Server 2005'
		WHEN @ProductVersion LIKE '8.%' THEN 'SQL Server 2000'
		WHEN @ProductVersion IS NULL THEN NULL
		ELSE 'SQL 7 or earlier'
			
		END

RETURN @Result

END
GO
