SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO
--=============================================
-- Copyright (C) 2021 Raul Gonzalez, @SQLDoubleG (RAG)
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
-- Author:		Raul Gonzalez, @SQLDoubleG (RAG)
-- Create date: 26/03/2021
-- Description:	This script will return information collected in sys.dm_exec_procedure_stats
--
-- Assumptions:	sys.dm_exec_procedure_stats is reset upon SQL Server restart
--				Due to this DMV volatility, it might not represent actual workload
--
-- Parameters:	
--				- @dbname
--
-- Log History:	
--				26/03/2021  RAG - Created
--
-- =============================================
SET NOCOUNT ON

DECLARE @dbname	    SYSNAME			= NULL

SELECT CASE WHEN database_id = 32767 then 'Resource' ELSE DB_NAME(database_id)END AS [database_name]
            ,OBJECT_SCHEMA_NAME(object_id,database_id) AS [schema_name]  
            ,OBJECT_NAME(object_id,database_id)AS [object_name]
            ,cached_time
            ,last_execution_time
            , ISNULL(NULLIF( CONVERT(VARCHAR(24),   (DATEDIFF(SECOND, cached_time, last_execution_time) / execution_count) / 3600 / 24 ),'0') + '.', '') + 
                        RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, cached_time, last_execution_time) / execution_count) / 3600 % 24 ), 2) + ':' + 
                        RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, cached_time, last_execution_time) / execution_count) / 60 % 60), 2) + ':' + 
                        RIGHT('00' + CONVERT(VARCHAR(24), (DATEDIFF(SECOND, cached_time, last_execution_time) / execution_count) % 60), 2) +
                        LEFT('.' + PARSENAME(CONVERT(VARCHAR(30), DATEDIFF(second, cached_time, last_execution_time) * 1. / execution_count), 1), 4) AS [executes_every_d.hh:mm:ss.ms]
            --, DATEDIFF(second, cached_time, last_execution_time) / execution_count AS Executes_every_n_seconds
            ,execution_count
            ,total_worker_time		/ execution_count AS avg_cpu
            ,total_elapsed_time		/ execution_count AS avg_elapsed
            ,total_logical_reads		/ execution_count AS avg_logical_reads
            ,total_logical_writes		/ execution_count AS avg_logical_writes
            ,total_physical_reads		/ execution_count AS avg_physical_reads
            , qp.query_plan
      FROM sys.dm_exec_procedure_stats  as ps
      OUTER APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
      WHERE database_id = db_id(@dbname)
      ORDER BY (DATEDIFF(SECOND, cached_time, last_execution_time) * 1. / execution_count) ASC, execution_count DESC