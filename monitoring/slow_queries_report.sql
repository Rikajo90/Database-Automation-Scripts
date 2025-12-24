-- =============================================
-- Slow Queries Monitoring Report
-- Author: Rika Afriyani
-- Purpose: Identify and analyze slow-running queries
-- =============================================

USE master;
GO

PRINT '============================================';
PRINT 'TOP 20 SLOWEST QUERIES REPORT';
PRINT 'Server: ' + @@SERVERNAME;
PRINT 'Date: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '============================================';
PRINT '';

-- Top 20 Slowest Queries by Average Execution Time
SELECT TOP 20
    qs.execution_count AS [Execution_Count],
    CAST(qs.total_elapsed_time / 1000000.0 AS DECIMAL(10,2)) AS [Total_Duration_Sec],
    CAST(qs.total_elapsed_time / qs.execution_count / 1000000.0 AS DECIMAL(10,2)) AS [Avg_Duration_Sec],
    CAST(qs.total_worker_time / 1000000.0 AS DECIMAL(10,2)) AS [Total_CPU_Sec],
    CAST(qs.total_worker_time / qs.execution_count / 1000000.0 AS DECIMAL(10,2)) AS [Avg_CPU_Sec],
    qs.total_logical_reads AS [Total_Logical_Reads],
    qs.total_logical_reads / qs.execution_count AS [Avg_Logical_Reads],
    qs.total_logical_writes AS [Total_Logical_Writes],
    DB_NAME(qt.dbid) AS [Database_Name],
    OBJECT_NAME(qt.objectid, qt.dbid) AS [Object_Name],
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS [Query_Text],
    qp.query_plan AS [Execution_Plan],
    qs.creation_time AS [Plan_Creation_Time],
    qs.last_execution_time AS [Last_Execution_Time]
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qs.total_elapsed_time / qs.execution_count > 100000 -- Queries taking > 0.1 sec avg
ORDER BY Avg_Duration_Sec DESC;

PRINT '';
PRINT '============================================';
PRINT 'Queries with Average Duration > 0.1 seconds';
PRINT 'Review these queries for optimization';
PRINT '============================================';
