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
-- Create date: 08/07/2013
-- Description:	Generates a new snapshot for the DBA database replication
--				and syncs all the subscribers
--
-- Change Log:	
--				23/10/2013 - RAG Added parameter @onlyDev to be able to push the publication only to DEV servers for testing
--				23/10/2013 - RAG Added validation to check if the snapshot has succeded to start the distribution
--				23/10/2013 - RAG Added PRINT statements in @debugging mode
--				23/10/2013 - RAG Include user views to be replicated
--				06/12/2013 - RAG Remove the part to run the distrib.exe as now replication runs continously, so we have only to 
--								generate a new snapshot.
--				10/12/2013 - RAG Included table valued functions to be included in the missing articles queries
--				14/07/2016 - SZO Removed no longer necessary comments from code block.
--
-- Values for MSsnapshot_history.runstatus : Taken From http://technet.microsoft.com/en-us/library/ms180128.aspx 
--				1 = Start.
--				2 = Succeed.
--				3 = In progress.
--				4 = Idle.
--				5 = Retry.
--				6 = Fail.

-- Usage:
--
--	DECLARE @onlyDev	bit = 1 -- deprecated
--	DECLARE @debugging	bit = 0
--
--	EXECUTE [dbo].[DBA_syncDBAreplication] 
--		@onlyDev	= @onlyDev
--		,@debugging	= @debugging
--	GO
-- =============================================
CREATE PROCEDURE [dbo].[DBA_syncDBAreplication]
	--@onlyDev		BIT		= 1 -- 
	--, @InstanceName	SYSNAME = NULL
	--, 
	@debugging	BIT		= 0 -- CALL THE SP WITH @debugging = 1 TO JUST PRINT OUT THE STATEMENTS
AS
BEGIN
	
	SET NOCOUNT ON

	--SET @onlyDev	= ISNULL(@onlyDev, 1)
	SET @debugging	= ISNULL(@debugging, 0)

	IF NOT EXISTS (SELECT 1 FROM DBA.sys.tables WHERE name = 'sysPublications') RETURN -100
	-- Executing from DBA database in any of the subscribers, return error

	DECLARE @Publisher			SYSNAME
			, @Subscriber		SYSNAME
			, @PublicationDB	SYSNAME = 'DBA'
			, @SubscriptionDB	SYSNAME = 'DBA'
			, @Publication		SYSNAME = 'DBA'
			, @PublicationID	INT		
			, @cmd				NVARCHAR(1000)
			--, @numDBs			INT
			--, @countDBs		INT = 1
			, @numMissing		INT
			, @countMissing		INT = 1
			, @articleName		SYSNAME
			, @schemaName		SYSNAME
			, @ownerName		SYSNAME
			, @publicationType	SYSNAME
			, @AgentRunStatus	INT = 0

	DECLARE @Subscribers TABLE(ID INT IDENTITY, InstanceName SYSNAME)
	
	SET @PublicationID = ( SELECT publication_id FROM distribution.dbo.MSpublications WHERE publication = @Publication )

	DECLARE @missingArticles TABLE 
		(ID			INT IDENTITY
		, Name		SYSNAME
		, obj_owner SYSNAME
		, sch_name	SYSNAME
		, type		SYSNAME)

	-- Get missing SP and UDF
	INSERT INTO @missingArticles 
		SELECT	o.name
				, sch.name
				, sch.name
				, CASE 
						WHEN o.type = 'P'						THEN 'proc schema only'
						WHEN o.type = 'V'						THEN 'view schema only'
						WHEN o.type IN ('FN', 'FT', 'FS', 'TF')	THEN 'func schema only'
					END 
			FROM DBA.sys.sysobjects AS o
				INNER JOIN DBA.sys.schemas AS sch
					ON o.uid = sch.principal_id
				INNER JOIN DBA.sys.objects AS ob
					ON ob.object_id = o.id
			WHERE o.type IN ('P','FN', 'FT', 'FS', 'TF', 'V')
				AND ob.is_ms_shipped = 0
				AND o.name NOT IN ( SELECT article FROM distribution.dbo.MSarticles WHERE publication_id = @PublicationID )
	
	SET @numMissing = @@ROWCOUNT

	WHILE @countMissing <= @numMissing BEGIN

		SELECT @articleName			= Name	
				, @schemaName		= sch_name
				, @ownerName		= obj_owner
				, @publicationType	= [type]
			FROM @missingArticles
			WHERE ID = @countMissing

		IF @debugging = 0 BEGIN
			-- Include the articles for the missing SP and UDF
			EXEC sp_addarticle 
				@publication				= @Publication
				, @article					= @articleName
				, @source_owner				= @ownerName
				, @source_object			= @articleName
				, @type						= @publicationType
				, @description				= null
				, @creation_script			= null
				, @pre_creation_cmd			= N'drop'
				, @schema_option			= 0x0000000008000001 -- Generates the object creation script (CREATE TABLE, ALTER PROCEDURE, and so on). This value is the default for stored procedure articles.
				, @destination_owner		= @ownerName
				, @force_invalidate_snapshot = 1
		END
		ELSE BEGIN
			PRINT 'EXEC sp_addarticle ' +
				'@publication				= ' + CONVERT(VARCHAR, @Publication) +
				', @article					= ' + CONVERT(VARCHAR, @articleName) +
				', @source_owner			= ' + CONVERT(VARCHAR, @ownerName) +
				', @source_object			= ' + CONVERT(VARCHAR, @articleName) +
				', @type					= ' + CONVERT(VARCHAR, @publicationType) +
				', @description				= null' +
				', @creation_script			= null' +
				', @pre_creation_cmd		= N''drop''' +
				', @schema_option			= 0x0000000008000001' +
				', @destination_owner		= @ownerName' +
				', @force_invalidate_snapshot = 1'			
		END
		SET @countMissing = @countMissing + 1
	END 


	SET @Publisher = (SELECT @@SERVERNAME FROM DBA.dbo.sysPublications WHERE name = 'DBA')

	IF @debugging = 0 BEGIN 
		-- Generate a new snapshot
		EXEC DBA.sys.sp_startpublication_snapshot @Publication
		
	END 
	ELSE BEGIN
		PRINT 'EXEC DBA.sys.sp_startpublication_snapshot ' + CONVERT(VARCHAR, @Publication)
	END

	IF @AgentRunStatus = 6 BEGIN
		RAISERROR ('The Publication Snapshot Failed', 16, 1, 1)
		RETURN -200
	END

END 




GO
