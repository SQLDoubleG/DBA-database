SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE PROCEDURE [dbo].[sp_fixeddrives]
AS
BEGIN

	SET NOCOUNT ON

	CREATE TABLE #DrvLetter (
		Drive VARCHAR(500))

	CREATE TABLE #DrvInfo (
		Drive			VARCHAR(500) NULL
		, [FreeMB]		INT
		, [TotalMB]		INT
		, [VolumeName]	VARCHAR(64))

	DECLARE @capacityChIx	INT
	DECLARE @captionChIx	INT
	DECLARE @freeSpaceChIx	INT
	DECLARE @lableChIx		INT

	INSERT INTO #DrvLetter
		EXEC xp_cmdshell 'wmic volume where drivetype="3" get caption, freespace, capacity, label'

	SELECT @capacityChIx		= CHARINDEX('Capacity'	, Drive) 
			, @captionChIx		= CHARINDEX('Caption'	, Drive) 
			, @freeSpaceChIx	= CHARINDEX('FreeSpace'	, Drive) 
			, @lableChIx		= CHARINDEX('Label'		, Drive) 
		FROM #DrvLetter
		WHERE Drive LIKE '%Capacity%'

	DELETE
		FROM #DrvLetter
		WHERE Drive IS NULL OR LEN(Drive) < 4 OR Drive LIKE '%Capacity%' OR Drive LIKE  '%\\%\Volume%'

	INSERT INTO #DrvInfo (TotalMB, Drive, FreeMB, VolumeName)
		SELECT TotalSize	= CAST(SUBSTRING(Drive,@capacityChIx, @captionChIx - @capacityChIx) AS BIGINT) / 1024 / 1024
				, Drive		= SUBSTRING(Drive, @captionChIx, @freeSpaceChIx - @captionChIx)
				, FreeSpace = CAST(SUBSTRING(Drive, @freeSpaceChIx, @lableChIx - @freeSpaceChIx) AS BIGINT) / 1024 / 1024
				, Label		= SUBSTRING(Drive, @lableChIx, LEN(Drive) - @lableChIx)
			FROM #DrvLetter 

	SELECT * 
		FROM #DrvInfo 
		ORDER BY Drive

	DROP TABLE #DrvLetter
	DROP TABLE #DrvInfo

END
GO
