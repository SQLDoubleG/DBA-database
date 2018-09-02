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
-- Author:      Raul Gonzalez @SQLDoubleG
-- Create date: 25/05/2016
-- Description: Returns the content of a Extended Event target file in a table format according to the current definition of the session
--
-- Remarks: 
--              - The session must exist in the server and so must the file in a place we can access
--              - Depending on the amount of data this process may take very long, it is recommended not to use in production systems
--              - You can offload this task by generating the query using the parameter @debugging = 1 and copying the file to another server.
--
-- Parameters:
--              - @sessionName  -> name of the extended event session
--              - @filePath     -> full path (including name) of the target file
--              - @debugging    -> will print the statement or execute it
--
-- Log History: 
--              25/05/2016 RAG - Created
--              31/03/2017 RAG - Allow 'xml_deadlock_report' events to be returned in a way you can copy/paste and save as (.xdl) file
--									for further analysis.
--              07/06/2017 RAG - Added event_timestamp column
--              08/06/2017 RAG - Return all events that return XML in XML format
--
-- Copyright:   (C) 2016 Raul Gonzalez (@SQLDoubleG http://www.sqldoubleg.com)
--
--              THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
--              ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
--              TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
--              PARTICULAR PURPOSE.
--
--              THE AUTHOR SHALL NOT BE LIABLE TO YOU OR ANY THIRD PARTY FOR ANY INDIRECT, 
--              SPECIAL, INCIDENTAL, PUNITIVE, COVER, OR CONSEQUENTIAL DAMAGES OF ANY KIND
--
--              YOU MAY ALTER THIS CODE FOR YOUR OWN *NON-COMMERCIAL* PURPOSES. YOU MAY
--              REPUBLISH ALTERED CODE AS LONG AS YOU INCLUDE THIS COPYRIGHT AND GIVE DUE CREDIT. 
--
-- =============================================
CREATE PROCEDURE [dbo].[DBA_ExtendedEventFileReader]
    @sessionName    SYSNAME       
    , @filePath     NVARCHAR(512) 
    , @debugging    BIT             = 0 -- Set to 0 to run the query, otherwise PRINT the statement
AS
   
DECLARE @sql				NVARCHAR(MAX)
  
DECLARE @actionsList		NVARCHAR(MAX)
DECLARE @actionsListFilter	NVARCHAR(MAX)
DECLARE @actionsListColumns	NVARCHAR(MAX)
  
DECLARE @eventsList			NVARCHAR(MAX)
DECLARE @eventsListFilter	NVARCHAR(MAX)
DECLARE @eventsListColumns	NVARCHAR(MAX)
   
-- Get actions from the Session
SET @actionsList		= (SELECT STUFF((SELECT DISTINCT ', ' + QUOTENAME(a.name)
                                FROM sys.server_event_sessions AS s
                                    LEFT JOIN sys.server_event_session_events AS e
                                        ON e.event_session_id = s.event_session_id
                                    INNER JOIN sys.server_event_session_actions AS a
                                        ON a.event_id = e.event_id
                                            AND e.event_session_id = a.event_session_id 
                                WHERE s.name = @sessionName
                            FOR XML PATH('')), 1, 2, ''))
   
SET @actionsListFilter	= REPLACE(REPLACE(@actionsList, '[', ''''), ']', '''')
SET @actionsListColumns = REPLACE(@actionsList, '[', 't_action.[')
   
-- Get Payload 
-- This to return events that return XML in XML format, just for the final query
SET @eventsListColumns	= (SELECT STUFF(
								(SELECT DISTINCT ', ' + 
										CASE WHEN c.type_name = 'XML' THEN 'CONVERT(XML, ' + QUOTENAME(c.name) + ') AS ' + QUOTENAME(c.name)
											ELSE 't_data.' + QUOTENAME(c.name)
										END
									FROM sys.server_event_sessions AS s
										LEFT JOIN sys.server_event_session_events AS e
											ON e.event_session_id = s.event_session_id
										LEFT JOIN sys.dm_xe_objects AS o
											ON o.name = e.name
										LEFT JOIN sys.dm_xe_object_columns AS c
											ON c.object_name = o.name
									WHERE s.name = @sessionName
										AND c.column_type <> 'readonly'
										AND ISNULL(column_value, 'true') = 'true'
								FOR XML PATH('')), 1, 2, ''))

SET @eventsList			= (SELECT STUFF(
								(SELECT DISTINCT ', ' + QUOTENAME(c.name)
									FROM sys.server_event_sessions AS s
										LEFT JOIN sys.server_event_session_events AS e
											ON e.event_session_id = s.event_session_id
										LEFT JOIN sys.dm_xe_objects AS o
											ON o.name = e.name
										LEFT JOIN sys.dm_xe_object_columns AS c
											ON c.object_name = o.name
									WHERE s.name = @sessionName
										AND c.column_type <> 'readonly'
										AND ISNULL(column_value, 'true') = 'true'
								FOR XML PATH('')), 1, 2, ''))
   
SET @eventsListFilter   = REPLACE(REPLACE(@eventsList, '[', ''''), ']', '''')
   
SET @sql = N'
   
IF OBJECT_ID(''tempdb..#ExEvent'') IS NOT NULL DROP TABLE #ExEvent
   
SELECT IDENTITY(INT,1,1) AS RowId, object_name AS event_name, CONVERT(XML,event_data) AS event_data
    INTO #ExEvent
FROM sys.fn_xe_file_target_read_file(N''' + @filePath + ''', null, null, null);
   
--=======================================================================================================
-- Usually here I would remove events I am not interested on, because the next query can take very long
--
--SELECT TOP 100 * FROM #ExEvent ORDER BY event_name
--
-- DELETE #ExEvent
--WHERE event_name [NOT] IN (N''rpc_completed'')
--=======================================================================================================
   
SELECT ISNULL(t_action.RowId, t_data.RowId) AS RowId
        , ISNULL(t_action.event_name, t_data.event_name) AS event_name
        , ISNULL(t_action.event_timestamp, t_data.event_timestamp) AS event_timestamp
        , ' + @actionsListColumns + N'
        , ' + @eventsListColumns + N'
    FROM (
            SELECT RowId, event_name, event_timestamp, ' + @actionsList + N'                 
                FROM (
                    SELECT RowId
                            , event_name
                            , T1.Loc.query(''.'').value(''(/event/@timestamp)[1]'', ''varchar(max)'') AS event_timestamp
                            , T2.Loc.query(''.'').value(''(/action/@name)[1]'', ''varchar(max)'')AS att_name
                            , T2.Loc.query(''.'').value(''(/action/value)[1]'', ''varchar(max)'')AS att_value
						FROM   #ExEvent
							CROSS APPLY event_data.nodes(''/event'') as T1(Loc) 
							CROSS APPLY event_data.nodes(''/event/action'') as T2(Loc) 
						WHERE T2.Loc.query(''.'').value(''(/action/@name)[1]'', ''varchar(max)'') 
							IN (' + @actionsListFilter  + N')
                    ) AS SourceTable
                        PIVOT(
                            MAX(att_value)
                            FOR att_name IN (' + @actionsList + N')
                    ) AS PivotTable
            ) AS t_action
           
        -- Full outer because it might be no events selected only the payload
        FULL OUTER JOIN (
            SELECT RowId, event_name, event_timestamp, ' + @eventsList + N'
                FROM (
                    SELECT RowId
                            , event_name
                            , T1.Loc.query(''.'').value(''(/event/@timestamp)[1]'', ''varchar(max)'') AS event_timestamp
                            , T3.Loc.query(''.'').value(''(/data/@name)[1]'', ''varchar(max)'') AS att_name
                            , CASE 
									-- deadlock report in xml to allow it to be saved as xdl
									WHEN event_name = ''xml_deadlock_report'' 
										THEN CONVERT(NVARCHAR(MAX), event_data.query(''/event/data/value/deadlock'')) 
									-- rest of events that return xml
									WHEN event_name IN (SELECT object_name FROM sys.dm_xe_object_columns
															WHERE type_name = ''xml'' AND name NOT IN (''xml_deadlock_report''))
										THEN CONVERT(NVARCHAR(MAX), event_data.query(''/event'')) 
									-- rest of events
									ELSE T3.Loc.query(''.'').value(''(/data/value)[1]'', ''varchar(max)'') 
								END AS att_value
                        FROM   #ExEvent
							CROSS APPLY event_data.nodes(''/event'') as T1(Loc) 
							CROSS APPLY event_data.nodes(''/event/data'') as T3(Loc) 
                        WHERE T3.Loc.query(''.'').value(''(/data/@name)[1]'', ''varchar(max)'') 
                            IN (' + @eventsListFilter  + N')
                        ) AS SourceTable
                            PIVOT (
                            MAX(att_value)
                                FOR att_name IN (' + @eventsList + N')
                        ) AS PivotTable
            ) AS t_data
            ON t_data.RowId = t_action.RowId
'
   
IF @debugging = 1 
    SELECT CONVERT(XML, @sql)
ELSE
    EXECUTE sp_executesql @sql
GO
