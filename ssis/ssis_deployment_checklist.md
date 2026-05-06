# 📦 SSIS Deployment Checklist

Step-by-step checklist for deploying SSIS packages across DEV → STG → PRD environments.

> All server names, database names, and package names in this guide use dummy data.

---

## Pre-Deployment Checklist

- [ ] Backup existing SSIS packages from target environment
- [ ] Verify SQL Server Agent service is running on target server
- [ ] Confirm SSISDB catalog exists on target instance
- [ ] Verify connection managers configuration
- [ ] Confirm environment variables are configured correctly
- [ ] Get deployment approval from team lead

---

## Step 1 — Export Package from DEV

1. Open SSMS → Connect to DEV instance
2. Navigate to **Integration Services Catalogs** → **SSISDB**
3. Right-click target project → **Export**
4. Save `.ispac` file to local machine

```sql
-- Verify package exists in DEV
SELECT
    f.name        AS folder_name,
    p.name        AS project_name,
    pkg.name      AS package_name,
    pkg.description,
    p.deployed_by_name,
    p.last_deployed_time
FROM SSISDB.catalog.packages pkg
JOIN SSISDB.catalog.projects p ON pkg.project_id = p.project_id
JOIN SSISDB.catalog.folders f ON p.folder_id = f.folder_id
ORDER BY f.name, p.name
```

---

## Step 2 — Deploy to Target Environment (STG/PRD)

1. Open SSMS → Connect to target instance (STG or PRD)
2. Navigate to **Integration Services Catalogs** → **SSISDB**
3. Right-click target folder → **Deploy Project**
4. Select the `.ispac` file exported from Step 1
5. Follow deployment wizard → click **Deploy**

```sql
-- Verify deployment result
SELECT TOP 10
    operation_id,
    operation_type,
    status,
    CASE status
        WHEN 1 THEN 'Created'
        WHEN 2 THEN 'Running'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'Failed'
        WHEN 5 THEN 'Pending'
        WHEN 6 THEN 'Ended Unexpectedly'
        WHEN 7 THEN 'Succeeded'
        WHEN 8 THEN 'Stopping'
        WHEN 9 THEN 'Completed'
    END             AS status_desc,
    start_time,
    end_time
FROM SSISDB.catalog.operations
ORDER BY start_time DESC
```

---

## Step 3 — Configure Environment Variables

```sql
-- Check existing environment variables on target
SELECT
    e.name          AS environment_name,
    ev.name         AS variable_name,
    ev.type,
    ev.sensitive,
    ev.value
FROM SSISDB.catalog.environments e
JOIN SSISDB.catalog.environment_variables ev
    ON e.environment_id = ev.environment_id
ORDER BY e.name, ev.name
```

---

## Step 4 — Configure Connection Managers

After deployment, update connection strings for the target environment:

1. Right-click deployed project → **Configure**
2. Go to **Connection Managers** tab
3. Update server name, database name, and credentials
4. Click **OK**

```sql
-- Verify connection manager configuration
SELECT
    op.object_name,
    p.parameter_name,
    p.parameter_value,
    p.value_set,
    p.referenced_variable_name
FROM SSISDB.catalog.object_parameters p
JOIN SSISDB.catalog.projects op
    ON p.project_id = op.project_id
WHERE p.object_type = 20 -- connection manager
ORDER BY op.object_name, p.parameter_name
```

---

## Step 5 — Test Package Execution

```sql
-- Execute package manually via T-SQL
DECLARE @execution_id BIGINT

EXEC SSISDB.catalog.create_execution
    @folder_name = N'DummyFolder',
    @project_name = N'DummyProject',
    @package_name = N'DummyPackage.dtsx',
    @execution_id = @execution_id OUTPUT

EXEC SSISDB.catalog.start_execution @execution_id

-- Check execution result
SELECT
    operation_id,
    status,
    start_time,
    end_time,
    DATEDIFF(SECOND, start_time, end_time) AS duration_seconds
FROM SSISDB.catalog.executions
WHERE operation_id = @execution_id
```

---

## Step 6 — Post-Deployment Verification

```sql
-- Check execution history (last 10 runs)
SELECT TOP 10
    ex.operation_id,
    f.name          AS folder_name,
    p.name          AS project_name,
    ex.package_name,
    CASE ex.status
        WHEN 1 THEN 'Created'
        WHEN 2 THEN 'Running'
        WHEN 4 THEN 'Failed'
        WHEN 7 THEN 'Succeeded'
        WHEN 9 THEN 'Completed'
    END             AS status_desc,
    ex.start_time,
    ex.end_time,
    DATEDIFF(SECOND, ex.start_time, ex.end_time) AS duration_seconds
FROM SSISDB.catalog.executions ex
JOIN SSISDB.catalog.projects p ON ex.project_id = p.project_id
JOIN SSISDB.catalog.folders f ON p.folder_id = f.folder_id
ORDER BY ex.start_time DESC

-- Check execution messages if failed
SELECT
    operation_id,
    message_time,
    message_type,
    message_source_type,
    message
FROM SSISDB.catalog.operation_messages
WHERE operation_id = @execution_id
  AND message_type = 120 -- errors only
ORDER BY message_time
```

---

## Post-Deployment Checklist

- [ ] Package executed successfully in target environment
- [ ] Execution logs reviewed — no errors
- [ ] SQL Agent Job updated to use new package version
- [ ] Notify team that deployment is complete
- [ ] Update deployment documentation

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|---|---|---|
| Connection manager error | Wrong server/DB name in target env | Reconfigure connection manager |
| Assembly not found | DLL version mismatch | Register correct DLL version on target server |
| Environment variable not set | Variable missing in target env | Add missing variable in SSISDB environment |
| Package validation failed | Reference to non-existent object | Check all source/destination tables exist |
| Access denied | Missing permissions on target DB | Grant required permissions to service account |

---

## 👤 Author

**Rika Afriyani** — Junior DBA  
💼 [LinkedIn](https://linkedin.com/in/rika-afriyani-b86457191) | 🐙 [GitHub](https://github.com/Rikajo90)
