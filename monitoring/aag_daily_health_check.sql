-- ============================================================
-- AAG Daily Health Check
-- Description : Daily monitoring queries for SQL Server
--               Always On Availability Groups (AAG)
-- Author      : Rika Afriyani
-- Note        : All server/database names are dummy data
-- ============================================================


-- 1. CHECK AAG OVERALL HEALTH
-- Expected: synchronization_health_desc = HEALTHY
SELECT
    ag.name                             AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc,
    ars.operational_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ar.replica_id = ars.replica_id
ORDER BY ag.name, ars.role_desc


-- 2. CHECK DATABASE SYNC STATE PER REPLICA
-- Expected: synchronization_state_desc = SYNCHRONIZED
SELECT
    ag.name                             AS ag_name,
    db.name                             AS database_name,
    ar.replica_server_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.log_send_queue_size             AS log_send_queue_kb,
    drs.redo_queue_size                 AS redo_queue_kb,
    drs.log_send_rate                   AS log_send_rate_kb_per_sec,
    drs.redo_rate                       AS redo_rate_kb_per_sec
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar
    ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag
    ON ar.group_id = ag.group_id
JOIN sys.databases db
    ON drs.database_id = db.database_id
ORDER BY ag.name, db.name


-- 3. CHECK PRIMARY REPLICA PER AG
SELECT
    ag.name                             AS ag_name,
    ar.replica_server_name              AS primary_replica,
    ars.role_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ar.replica_id = ars.replica_id
WHERE ars.role_desc = 'PRIMARY'


-- 4. CHECK SQL AGENT JOB STATUS (LAST 24 HOURS)
-- Expected: run_status = 1 (Succeeded)
SELECT TOP 20
    j.name                              AS job_name,
    jh.run_date,
    jh.run_time,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
    END                                 AS run_status,
    jh.run_duration,
    jh.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh
    ON j.job_id = jh.job_id
WHERE jh.step_id = 0
  AND jh.run_date >= CONVERT(INT, CONVERT(VARCHAR, GETDATE()-1, 112))
ORDER BY jh.run_date DESC, jh.run_time DESC


-- 5. CHECK BACKUP STATUS PER DATABASE
-- Expected: all databases have recent backup
SELECT
    db.name                             AS database_name,
    MAX(bs.backup_finish_date)          AS last_backup_date,
    DATEDIFF(HOUR, MAX(bs.backup_finish_date), GETDATE())
                                        AS hours_since_last_backup,
    bs.type                             AS backup_type
FROM sys.databases db
LEFT JOIN msdb.dbo.backupset bs
    ON db.name = bs.database_name
WHERE db.database_id > 4 -- exclude system databases
GROUP BY db.name, bs.type
ORDER BY db.name, bs.type


-- 6. CHECK BLOCKING SESSIONS
-- Expected: no results (no blocking)
SELECT
    blocking.session_id                 AS blocking_session_id,
    blocked.session_id                  AS blocked_session_id,
    blocked.wait_time / 1000            AS wait_time_seconds,
    blocked.wait_type,
    SUBSTRING(st.text, 1, 200)          AS blocked_query
FROM sys.dm_exec_requests blocked
JOIN sys.dm_exec_sessions blocking
    ON blocked.blocking_session_id = blocking.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) st
WHERE blocked.blocking_session_id > 0
