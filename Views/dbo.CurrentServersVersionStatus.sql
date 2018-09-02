SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW [dbo].[CurrentServersVersionStatus]
AS 

	SELECT server_name
			, v.SQLServerProduct
			, v.ResourceVersion AS CurrentResourceVersion
			, v.Description AS CurrentProductDescription
			, sp.ResourceVersion AS LatestSPResourceVersion
			, sp.Description AS LatestSPResourceDescription
			, c.ResourceVersion AS LatestResourceVersion
			, vv.Description AS LatestResourceDescription
		FROM dbo.ServerProperties AS s
			LEFT JOIN dbo.SQLServerProductVersions AS v
				ON v.ResourceVersion= CONVERT(VARCHAR(20), s.ResourceVersion)
			LEFT JOIN dbo.CurrentSQLServerProductVersions AS c
				ON c.SQLServerProduct = v.SQLServerProduct
			LEFT JOIN dbo.SQLServerProductVersions AS vv
				ON vv.ResourceVersion= c.ResourceVersion
			LEFT JOIN dbo.CurrentSQLServerServicePack AS sp
				ON sp.SQLServerProduct = v.SQLServerProduct
GO
