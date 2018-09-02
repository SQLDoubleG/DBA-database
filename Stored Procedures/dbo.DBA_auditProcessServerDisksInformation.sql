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
-- Author:		RAG
-- Create date: 11/02/2015
-- Description:	Process the disk information collected in [dbo].[ServerDisksInformation_Loading]
--
-- Log:
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_auditProcessServerDisksInformation] 
AS
BEGIN

	SET NOCOUNT ON

	IF NOT EXISTS (SELECT * FROM dbo.ServerDisksInformation_Loading) BEGIN
		RAISERROR ('The table [dbo].[ServerDisksInformation_Loading] is empty, please run [dbo].[DBA_auditGetServerDisksInformation] using parameter @insertAuditTables = 1 and the re run this procedure',16, 0, 0)
		RETURN -100
	END

	SELECT DISTINCT server_name 
		INTO #server_reached
		FROM dbo.ServerDisksInformation_Loading

	BEGIN TRY

		-- Workaround to create the temp table. it's too big I don't bother to write the whole piece.
		SELECT [Action],[server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime],[RowCheckSum]
			INTO #h
			FROM [dbo].[ServerDisksInformation_History]
			WHERE 1=0
		
		INSERT INTO #h ([Action],[server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime],[RowCheckSum])
		SELECT [Action],[server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime],[RowCheckSum]
			FROM (

			-- Get current information into the table
			MERGE INTO dbo.ServerDisksInformation AS t
				USING dbo.ServerDisksInformation_Loading AS s
					ON s.server_name = t.server_name
						AND s.Drive = t.Drive

				WHEN NOT MATCHED BY TARGET THEN 
					INSERT ([server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime])
					VALUES ([server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime])

				WHEN MATCHED THEN UPDATE
					SET t.[VolName]				= s.[VolName]
						, t.[FileSystem]		= s.[FileSystem]
						, t.[SizeMB]			= s.[SizeMB]
						, t.[FreeMB]			= s.[FreeMB]
						, t.[ClusterSize]		= s.[ClusterSize]						
						, t.[DataCollectionTime]= s.[DataCollectionTime]
						
				WHEN NOT MATCHED BY SOURCE 
					-- Either we don't care about that server any more or we reach the server but wans't there (deleted)
					AND (t.server_name NOT IN (SELECT server_name FROM [dbo].[vSQLServersToMonitor])  
						OR t.server_name IN (SELECT server_name FROM #server_reached)) THEN 
				DELETE				

			OUTPUT $action AS [Action], deleted.*) AS History 
		WHERE [Action] IN ('UPDATE', 'DELETE');			
		
		MERGE dbo.[ServerDisksInformation_History] AS t
			USING #h AS s
				ON s.server_name		= t.server_name
					AND s.[Drive]		= t.[Drive]
					AND s.RowCheckSum	= t.RowCheckSum
			WHEN NOT MATCHED THEN 
					INSERT ([Action],[server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime],[RowCheckSum])
					VALUES ([Action],[server_name],[Drive],[VolName],[FileSystem],[SizeMB],[FreeMB],[ClusterSize],[DataCollectionTime],[RowCheckSum]);
					
		TRUNCATE TABLE dbo.ServerDisksInformation_Loading

	END TRY
	BEGIN CATCH
		SELECT ERROR_MESSAGE();
	END CATCH;

END

GO
