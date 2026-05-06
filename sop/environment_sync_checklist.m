# 🔄 Environment Sync Checklist

Step-by-step checklist for synchronizing database environments DEV → STG → PRD.

> All server names, database names, and instance names in this guide use dummy data.

---

## Overview

| Item | Detail |
|---|---|
| **Purpose** | Ensure STG/PRD environment is in sync with DEV |
| **Scope** | Database schema, stored procedures, SSIS packages, logins |
| **PIC** | Database Administrator |
| **Estimated Duration** | 2-4 hours depending on scope |

---

## Pre-Sync Checklist

- [ ] Backup target environment database before starting
- [ ] Confirm DEV changes have been tested and approved
- [ ] Get deployment approval from team lead
- [ ] Notify application team about scheduled maintenance
- [ ] Verify disk space on target server is sufficient
- [ ] Schedule sync during off-peak hours

---

## Step 1 — Backup Target Environment

```sql
-- Full backup before sync
BACKUP DATABASE [TargetDB]
TO DISK = 'D:\Backup\TargetDB_PreSync_' 
    + REPLACE(CONVERT(VARCHAR, GETDATE(), 120), ':', '-') + '.bak'
WITH COMPRESSION, STATS = 10

-- Verify backup
RESTORE VERIFYONLY
FROM DISK = 'D:\Backup\TargetDB_PreSync.bak'
```

---

## Step 2 — Compare Schema Between Environments

```sql
-- Check tables in DEV vs STG/PRD
-- Run on DEV
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME

-- Check stored procedures
SELECT
    ROUTINE_SCHEMA,
    ROUTINE_NAME,
    LAST_ALTERED
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME

-- Check views
SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_SCHEMA, TABLE_NAME
```

---

## Step 3 — Run Migration Scripts

```sql
-- Always wrap DDL changes in transaction
BEGIN TRAN

-- Example: Add new column
ALTER TABLE dbo.SampleTable
ADD NewColumn NVARCHAR(100) NULL

-- Example: Create new stored procedure
CREATE OR ALTER PROCEDURE dbo.usp_SampleProcedure
AS
BEGIN
    SELECT 'Sample' AS Result
END

-- Verify changes before commit
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'SampleTable'
  AND COLUMN_NAME = 'NewColumn'

COMMIT TRAN
```

> ⚠️ **Important:** Always verify changes before `COMMIT`. Keep rollback script ready.

---

## Step 4 — Sync Logins & Users

```sql
-- Check logins on source (DEV)
SELECT
    name,
    type_desc,
    is_disabled,
    create_date
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G') -- SQL, Windows User, Windows Group
  AND name NOT LIKE '##%'
  AND name NOT IN ('sa', 'guest')
ORDER BY name

-- Check database users
SELECT
    dp.name AS user_name,
    dp.type_desc,
    roles.name AS role_name
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
LEFT JOIN sys.database_principals roles ON drm.role_principal_id = roles.principal_id
WHERE dp.type NOT IN ('R', 'A')
  AND dp.name NOT IN ('guest', 'INFORMATION_SCHEMA', 'sys', 'dbo')
ORDER BY dp.name
```

---

## Step 5 — Deploy SSIS Packages

Refer to [SSIS Deployment Checklist](../ssis/ssis_deployment_checklist.md) for detailed steps.

Quick summary:
- [ ] Export `.ispac` from DEV SSISDB
- [ ] Deploy to target SSISDB
- [ ] Reconfigure connection managers for target environment
- [ ] Update environment variables
- [ ] Test package execution

---

## Step 6 — Post-Sync Verification

```sql
-- Verify database is online
SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE name = 'TargetDB'

-- Check AAG sync status after changes
SELECT
    ag.name AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
ORDER BY ag.name

-- Run sanity check queries
SELECT TOP 10 * FROM dbo.SampleTable
ORDER BY CreatedDate DESC

-- Check SQL Agent jobs
SELECT TOP 10
    j.name AS job_name,
    CASE jh.run_status
        WHEN 1 THEN 'Succeeded'
        WHEN 0 THEN 'Failed'
    END AS status,
    jh.run_date,
    jh.run_time
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE jh.step_id = 0
ORDER BY jh.run_date DESC, jh.run_time DESC
```

---

## Post-Sync Checklist

- [ ] All migration scripts executed successfully
- [ ] Schema matches between environments
- [ ] Logins and users configured correctly
- [ ] SSIS packages deployed and tested
- [ ] SQL Agent jobs running successfully
- [ ] Application team confirmed no issues
- [ ] Document sync date, scope, and PIC

---

## Rollback Plan

If critical issues occur after sync:

1. Restore from pre-sync backup:

```sql
-- Restore database to pre-sync state
RESTORE DATABASE [TargetDB]
FROM DISK = 'D:\Backup\TargetDB_PreSync.bak'
WITH REPLACE, RECOVERY, STATS = 10
```

2. Notify application team immediately
3. Investigate root cause before retrying sync

---

## Common Issues

| Issue | Cause | Solution |
|---|---|---|
| Foreign key constraint error | Missing dependent table/data | Run scripts in correct order |
| Login already exists | Duplicate login sync | Skip or alter existing login |
| SSIS package failed after deploy | Wrong connection manager config | Reconfigure for target environment |
| AAG sync delayed after changes | Large schema changes | Monitor redo queue, wait for sync |
| Permission denied | Missing role assignment | Grant required permissions |

---

## 👤 Author

**Rika Afriyani** — Junior DBA  
💼 [LinkedIn](https://linkedin.com/in/rika-afriyani-b86457191) | 🐙 [GitHub](https://github.com/Rikajo90)
