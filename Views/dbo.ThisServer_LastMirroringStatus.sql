SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
CREATE VIEW [dbo].[ThisServer_LastMirroringStatus] AS

	SELECT [server_name]
			, [DatabaseName]
			, [mirroring_role]
			, [mirroring_role_desc]
			, [mirroring_state]
			, [mirroring_state_desc]
			, [mirroring_witness_state]
			, [mirroring_witness_state_desc]
			, [mirroring_safety_level]
			, [mirroring_safety_level_desc]
			, [mirroring_change_date]
	FROM [DBA].[dbo].[LastMirroringStatus]
	WHERE server_name = @@SERVERNAME





GO
