SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[CurrentSQLServerProductVersions]
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
						ORDER BY ReleaseDate DESC, ResourceVersion DESC) AS t

GO
