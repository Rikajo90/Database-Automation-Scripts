# 🔐 Credential Rotation SOP

Standard Operating Procedure for rotating Windows domain service account passwords used in SQL Server environments.

> All server names, database names, and account names in this guide use dummy data.

---

## Overview

| Item | Detail |
|---|---|
| **Trigger** | Scheduled rotation or security policy requirement |
| **Frequency** | Every 30-90 days depending on account type |
| **PIC** | Database Administrator |
| **Estimated Duration** | 30-60 minutes |

---

## Accounts in Scope

| Account | Usage | Rotation Frequency |
|---|---|---|
| `DOMAIN\svc_sqloltp` | SQL Server integration service account | 30 days |
| `DOMAIN\svc_sqlagent` | SQL Server Agent service account | 90 days |
| `DOMAIN\svc_sqlbackup` | Backup service account | 90 days |

---

## Pre-Rotation Checklist

- [ ] Confirm new password meets AD password policy
- [ ] Notify application team before starting
- [ ] Identify all systems using this account
- [ ] Schedule rotation during off-peak hours
- [ ] Prepare rollback plan

---

## Step 1 — Change Password in Active Directory

1. Login to Active Directory management tool
2. Navigate to the service account
3. Reset password with new value
4. Confirm password change successful

---

## Step 2 — Identify Dependencies in SQL Server

```sql
-- Check SQL Server login
SELECT name, type_desc, is_disabled, create_date
FROM sys.server_principals
WHERE name LIKE '%svc_sqloltp%'

-- Check SQL Agent Proxy
SELECT p.name AS proxy_name, c.credential_identity, p.enabled
FROM msdb.dbo.sysproxies p
JOIN sys.credentials c ON p.credential_id = c.credential_id
WHERE c.credential_identity LIKE '%svc_sqloltp%'

-- Check Windows Credential
SELECT name, credential_identity, create_date
FROM sys.credentials
WHERE credential_identity LIKE '%svc_sqloltp%'

-- Check Linked Server
SELECT s.name AS linked_server, l.remote_name
FROM sys.servers s
JOIN sys.linked_logins l ON s.server_id = l.server_id
WHERE l.remote_name LIKE '%svc_sqloltp%'
```

---

## Step 3 — Update Password in Application Config

```sql
-- Verify current value first
SELECT ConfigID, StringValue AS CurrentValue
FROM AppDB.dbo.SysConfig
WHERE ConfigID = 1

-- Update on PRIMARY replica only
BEGIN TRAN
UPDATE AppDB.dbo.SysConfig
SET StringValue = 'NewPassword123'
WHERE ConfigID = 1

-- Verify before commit
SELECT ConfigID, StringValue AS NewValue
FROM AppDB.dbo.SysConfig
WHERE ConfigID = 1
COMMIT TRAN
```

> ⚠️ **Important:**
> - Always run UPDATE on **PRIMARY replica** only — changes sync automatically to secondary
> - If database is NOT in Distributed AG, run UPDATE separately on **each AG's primary**
> - Always use `BEGIN TRAN` and verify before `COMMIT`

---

## Step 4 — Update SQL Agent Proxy (if applicable)

```sql
-- Update proxy credential
ALTER CREDENTIAL [CredentialName]
WITH IDENTITY = 'DOMAIN\svc_sqloltp',
SECRET = 'NewPassword123'
```

---

## Step 5 — Sanity Check

```sql
-- Check SQL Agent jobs ran successfully after rotation
SELECT TOP 10
    j.name AS job_name,
    jh.run_date,
    jh.run_time,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
    END AS run_status,
    jh.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE jh.step_id = 0
ORDER BY jh.run_date DESC, jh.run_time DESC

-- Check for any failed jobs after rotation
SELECT
    j.name AS job_name,
    jh.run_date,
    jh.run_time,
    jh.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE jh.step_id = 0
  AND jh.run_status = 0 -- Failed
  AND jh.run_date >= CONVERT(INT, CONVERT(VARCHAR, GETDATE(), 112))
ORDER BY jh.run_date DESC
```

---

## Post-Rotation Checklist

- [ ] AD password changed successfully
- [ ] Application config table updated on all primary replicas
- [ ] SQL Agent jobs running successfully
- [ ] SSIS packages executing without errors
- [ ] Application team confirmed no issues
- [ ] Document rotation date and PIC

---

## Rollback Plan

If issues occur after rotation:

1. Revert password in AD to previous value
2. Revert application config table:

```sql
BEGIN TRAN
UPDATE AppDB.dbo.SysConfig
SET StringValue = 'OldPassword123'
WHERE ConfigID = 1

SELECT ConfigID, StringValue FROM AppDB.dbo.SysConfig
WHERE ConfigID = 1
COMMIT TRAN
```

3. Notify application team
4. Investigate root cause before retrying

---

## Common Issues

| Issue | Cause | Solution |
|---|---|---|
| SSIS package fails after rotation | Config table not updated | Re-run Step 3 |
| SQL Agent job fails | Proxy credential not updated | Re-run Step 4 |
| Application login error | Config updated on wrong replica | Check primary replica and re-run |
| AD password rejected | Does not meet complexity policy | Use stronger password |

---

## 👤 Author

**Rika Afriyani** — Junior DBA  
💼 [LinkedIn](https://linkedin.com/in/rika-afriyani-b86457191) | 🐙 [GitHub](https://github.com/Rikajo90)
