SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
-- =============================================
-- Author:		Microsoft 
--
-- Original URL: http://support.microsoft.com/kb/918992
--
-- Description: SP used by [dbo].[DBA_help_revlogin] to generate hashed passwords for logins to be transferred from one server to another
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_hexadecimal]
	@binvalue VARBINARY(256),
	@hexvalue VARCHAR (514) OUTPUT
AS
BEGIN	
	
	SET NOCOUNT ON

	DECLARE @charvalue	VARCHAR (514)	= '0x'
	DECLARE @i			INT				= 1
	DECLARE @length		INT				= DATALENGTH (@binvalue)
	DECLARE @hexstring	CHAR(16)		= '0123456789ABCDEF'
	
	WHILE (@i <= @length) BEGIN
		DECLARE @tempint int
		DECLARE @firstint int
		DECLARE @secondint int
		SELECT @tempint = CONVERT(int, SUBSTRING(@binvalue,@i,1))
		SELECT @firstint = FLOOR(@tempint/16)
		SELECT @secondint = @tempint - (@firstint*16)
		SELECT @charvalue = @charvalue +
		SUBSTRING(@hexstring, @firstint+1, 1) +
		SUBSTRING(@hexstring, @secondint+1, 1)
		SELECT @i = @i + 1
	END

	SELECT @hexvalue = @charvalue
END



GO
