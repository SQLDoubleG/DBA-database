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
-- Create date: 14/01/2014
-- Description:	Gets info for given database or all if not provided.
--				The sp returns 1 resultset 
--					- database_name 
--					- database_size_KB
--					- unallocated_space_KB
--					- reserved_KB
--					- data_KB
--					- index_size_KB
--					- unused_KB
--
-- Remarks:
--				This sp is used by [dbo].[DBA_auditGetDatabaseInformation], so any change here should be reflected there too
--
-- Assumptions:	This sp uses calculations taken from sys.sp_spaceused
--
-- Change Log:	
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_spaceused]
	@dbname			SYSNAME = NULL
AS
BEGIN

	SET NOCOUNT ON

	CREATE TABLE #rs1 (
		database_name			SYSNAME
		, database_size_KB		BIGINT
		, unallocated_space_KB	BIGINT
	)
	
	CREATE TABLE #rs2 (
		database_name		SYSNAME
		, reserved_KB		BIGINT
		, data_KB			BIGINT
		, index_KB			BIGINT
		, log_KB			BIGINT
		, used_KB			BIGINT
		, unused_KB			BIGINT
	)

	DECLARE @databases TABLE (ID	INT IDENTITY PRIMARY KEY
							, name	SYSNAME)

	DECLARE @countDBs	INT = 1
			, @numDBs	INT

	DECLARE @sql	NVARCHAR(MAX) 

	INSERT INTO @databases (name)
		SELECT name 
			FROM sys.databases 
			WHERE state = 0
				AND name LIKE ISNULL(@dbname, name)

	SET @numDBs = @@ROWCOUNT

	WHILE @countDBs <= @numDBs BEGIN
	
		SET @dbname	= (SELECT name FROM @databases WHERE ID = @countDBs)

		SET @sql = N'
			USE ' + QUOTENAME(@dbname) + N'	

			DECLARE @pages				BIGINT
					, @dbsize			BIGINT
					, @logsize			BIGINT
					, @reservedpages	BIGINT
					, @usedpages		BIGINT
					, @rowCount			BIGINT
	
			SELECT @dbsize		= SUM(CONVERT(BIGINT,CASE WHEN status & 64 = 0 THEN size else 0 end))
					, @logsize	= SUM(CONVERT(BIGINT,CASE WHEN status & 64 <> 0 THEN size else 0 end))
				FROM dbo.sysfiles

			SELECT @reservedpages	= SUM(a.total_pages)
					, @usedpages	= SUM(a.used_pages)
					, @pages		= SUM(	CASE
												-- XML-Index and FT-Index internal tables are not considered "data", but is part of "index_size"
												WHEN it.internal_type IN (202,204,211,212,213,214,215,216) THEN 0
												WHEN a.type <> 1 THEN a.used_pages
												WHEN p.index_id < 2 THEN a.data_pages
												Else 0
											END )
				FROM sys.partitions p 
					inner join sys.allocation_units a 
						on p.partition_id = a.container_id
					left join sys.internal_tables it 
						on p.object_id = it.object_id

			/* unallocated space could not be negative */
			INSERT INTO #rs1
				SELECT database_name		= DB_NAME()
						, database_size		= (CONVERT (dec (15,2),@dbsize) + CONVERT (dec (15,2),@logsize)) * 8 -- 8192 / 1048576
						, unallocated_space = CASE 
													WHEN @dbsize >= @reservedpages THEN (CONVERT (dec (15,2),@dbsize) - CONVERT (dec (15,2),@reservedpages)) * 8 -- 8192 / 1048576 
													ELSE 0 
												END

			/*
			**  Now calculate the SUMmary data.
			**  reserved: SUM(reserved) where indid in (0, 1, 255)
			** data: SUM(data_pages) + SUM(text_used)
			** index: SUM(used) where indid in (0, 1, 255) - data
			** unused: SUM(reserved) - SUM(used) where indid in (0, 1, 255)
			*/
			INSERT INTO #rs2
				SELECT database_name	= DB_NAME()
						, reserved		= (@reservedpages) * 8
						, data			= (@pages) * 8
						, index_size	= (@usedpages - @pages) * 8
						, log_KB		= (@logsize) * 8
						, used			= (@usedpages) * 8
						, unused		= (@reservedpages - @usedpages) * 8

		' 
		EXECUTE sp_executesql @sql
		SET @countDBs = @countDBs + 1
	END

	SELECT rs1.database_name
			, rs1.database_size_KB
			, rs1.unallocated_space_KB
			, rs2.reserved_KB
			, rs2.data_KB
			, rs2.index_KB
			, rs2.log_KB
			, rs2.used_KB
			, rs2.unused_KB
		FROM #rs1 AS rs1
			INNER JOIN #rs2 as rs2
				ON rs1.database_name = rs2.database_name

	DROP TABLE #rs1
	DROP TABLE #rs2
	
END



GO
