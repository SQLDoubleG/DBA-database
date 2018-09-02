SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[CurrentSQLServerServicePack]
AS 

	SELECT DISTINCT s.[SQLServerProduct]
			, t.ResourceVersion
			, t.[FileVersion]
			, t.[Description]
			, t.ReleaseDate
		FROM [DBA].[dbo].[SQLServerProductVersions] AS s
		CROSS APPLY (SELECT TOP 1 [SQLServerProduct]
								, ResourceVersion
								, [FileVersion]
								, [Description]
								, ReleaseDate
						FROM [DBA].[dbo].[SQLServerProductVersions] AS ss
						WHERE ss.SQLServerProduct = s.SQLServerProduct
							AND Description LIKE SQLServerProduct + ' Service pack%'
							AND Description NOT LIKE '%CTP%'
							AND Description NOT LIKE '%beta%'
							AND Description NOT LIKE '%unidentified%'
							AND Description NOT LIKE '%patch%'
							AND Description NOT LIKE '%issue%'
						ORDER BY ReleaseDate DESC, ResourceVersion DESC) AS t

GO
