-- =============================================
-- Database Health Check Script
-- Author: Rika Afriyani
-- Purpose: Comprehensive health monitoring
-- Checks: Blocking, CPU, Memory, Disk Space, Corruption
-- =============================================

USE master;
GO

PRINT '============================================';
PRINT 'DATABASE HEALTH CHECK REPORT';
PRINT 'Server: ' + @@SERVERNAME;
PRINT 'Date: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '============================================';
PRINT '';

-- 1. Check for Blocking Sessions
PRINT '1. BLOCKING SESSIONS CHECK';
PRINT '-------------------------------------------';
IF EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
BEGIN
    PRINT '⚠️ WARNING: Blocking detected!';
    SELECT 
        blocking_session_id AS BlockingSessionID,
        session_id AS BlockedSessionID,
        wait_type AS WaitType,
        wait_time AS WaitTimeMS,
        wait_resource AS WaitResource,
        SUBSTRING(qt.text, (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(qt.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS BlockedQuery
    FROM sys.dm_exec_requests r
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
    WHERE blocking_session_id <> 0;
END
ELSE
BEGIN
    PRINT '✓ No blocking detected';
END
PRINT '';

-- 2. CPU Usage
PRINT '2. CPU USAGE CHECK';
PRINT '-------------------------------------------';
SELECT TOP 1
    SQLProcessUtilization AS [SQL_CPU_Usage_%],
    100 - SystemIdle - SQLProcessUtilization AS [Other_CPU_Usage_%],
    SystemIdle AS [System_Idle_%]
FROM (
    SELECT 
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
    FROM (
        SELECT CONVERT(XML, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '%<SystemHealth>%'
    ) AS x
) AS y
ORDER BY SQLProcessUtilization DESC;
PRINT '';

-- 3. Memory Usage
PRINT '3. MEMORY USAGE CHECK';
PRINT '-------------------------------------------';
SELECT 
    total_physical_memory_kb/1024 AS [Total_Memory_MB],
    available_physical_memory_kb/1024 AS [Available_Memory_MB],
    total_page_file_kb/1024 AS [Total_PageFile_MB],
    available_page_file_kb/1024 AS [Available_PageFile_MB],
    system_memory_state_desc AS [Memory_State]
FROM sys.dm_os_sys_memory;
PRINT '';

-- 4. Database File Sizes
PRINT '4. DATABASE FILE SIZES';
PRINT '-------------------------------------------';
SELECT 
    DB_NAME(database_id) AS [DatabaseName],
    name AS [FileName],
    physical_name AS [FilePath],
    size * 8 / 1024 AS [CurrentSize_MB],
    CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 8 / 1024 AS [UsedSpace_MB],
    (size * 8 / 1024) - (CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 8 / 1024) AS [FreeSpace_MB],
    CAST(ROUND(((size * 8 / 1024) - (CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 8 / 1024)) * 100.0 / (size * 8 / 1024), 2) AS DECIMAL(5,2)) AS [FreeSpace_%]
FROM sys.database_files
ORDER BY UsedSpace_MB DESC;
PRINT '';

-- 5. Last Backup Status
PRINT '5. LAST BACKUP STATUS';
PRINT '-------------------------------------------';
SELECT 
    d.name AS [DatabaseName],
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS [Last_Full_Backup],
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS [Last_Diff_Backup],
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS [Last_Log_Backup],
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS [Hours_Since_Full]
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name
WHERE d.database_id > 4 -- Exclude system databases
GROUP BY d.name
ORDER BY Hours_Since_Full DESC;
PRINT '';

-- 6. Failed Jobs (Last 24 hours)
PRINT '6. FAILED JOBS (Last 24 hours)';
PRINT '-------------------------------------------';
IF EXISTS (
    SELECT 1 
    FROM msdb.dbo.sysjobhistory jh
    JOIN msdb.dbo.sysjobs j ON jh.job_id = j.job_id
    WHERE jh.run_status = 0
    AND jh.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112))
)
BEGIN
    PRINT '⚠️ WARNING: Failed jobs detected!';
    SELECT 
        j.name AS [JobName],
        CONVERT(VARCHAR(20), 
            CAST(CAST(jh.run_date AS VARCHAR(8)) AS DATETIME) + 
            CAST(STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS DATETIME), 
            120) AS [FailureTime],
        jh.message AS [ErrorMessage]
    FROM msdb.dbo.sysjobhistory jh
    JOIN msdb.dbo.sysjobs j ON jh.job_id = j.job_id
    WHERE jh.run_status = 0
    AND jh.run_date >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY, -1, GETDATE()), 112))
    ORDER BY jh.run_date DESC, jh.run_time DESC;
END
ELSE
BEGIN
    PRINT '✓ No failed jobs in last 24 hours';
END
PRINT '';

-- 7. Database Corruption Check
PRINT '7. DATABASE CORRUPTION CHECK';
PRINT '-------------------------------------------';
PRINT 'Running DBCC CHECKDB...';
DECLARE @DBName NVARCHAR(128);
DECLARE db_cursor CURSOR FOR 
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC('DBCC CHECKDB ([' + @DBName + ']) WITH NO_INFOMSGS, PHYSICAL_ONLY');
        PRINT '✓ ' + @DBName + ' - No corruption detected';
    END TRY
    BEGIN CATCH
        PRINT '⚠️ ERROR in ' + @DBName + ': ' + ERROR_MESSAGE();
    END CATCH
    
    FETCH NEXT FROM db_cursor INTO @DBName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
PRINT '';

PRINT '============================================';
PRINT 'HEALTH CHECK COMPLETED';
PRINT 'Time: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '============================================';
