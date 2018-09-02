SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

CREATE VIEW
	[dbo].[ThisServer_LastDBCCHistory]
AS
SELECT

-- arbitrary huge number for the TOP () so we can order by the database name
TOP ( 2147483647 )

	dh.ID,
	dh.server_name,
	dh.name,
	dh.DBCC_datetime,
	dh.DBCC_duration,	
	dh.isPhysicalOnly,	
	dh.isDataPurity
FROM DBA.dbo.DBCC_History as [dh]

-- only return the latest ID...
INNER JOIN
(
	SELECT 
		MAX( lst.ID ) as last_id,	
		lst.name as database_name
	FROM DBA.dbo.DBCC_History as [lst]	
	GROUP BY	
		lst.name
) as lst_info	ON	dh.ID	=	lst_info.last_id

ORDER BY
	dh.name	ASC;
GO
