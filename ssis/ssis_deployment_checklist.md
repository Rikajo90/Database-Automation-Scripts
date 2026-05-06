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
    f.name          AS folder_name,
    p.name          AS project_name,
    pkg.name        AS package_name,
    p.deployed_by_name,
    p.last_deployed_time
FROM SSISDB.catalog.packages pkg
JOIN SSISDB.catalog.projects p ON pkg.project_id = p.project_id
JOIN SSISDB.catalog.folders f ON p.folder_id = f.folder_id
ORDER BY f.name, p.name
```

---

## Step 2 — Pre-Deploy: Set DelayValidation = True

⚠️ **Critical step before deployment!**

Without `DelayValidation = True`, packages will fail validation before parameters are applied — causing connection errors even when the configuration is correct.

**Option A: Set via Visual Studio (recommended)**
1. Open `.dtsx` file in Visual Studio
2. Click each Connection Manager → Properties (F4)
3. Set `DelayValidation = True`
4. Repeat for all Connection Managers and Control Flow tasks
5. Rebuild and redeploy `.ispac`

**Option B: Set via PowerShell (bulk update)**

```powershell
# Set DelayValidation = True on all packages in a project folder
$folderPath = "C:\Projects\DummyProject\"
$dtxFiles = Get-ChildItem -Path $folderPath -Filter "*.dtsx" -Recurse

foreach ($file in $dtxFiles) {
    [xml]$xml = Get-Content $file.FullName
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("DTS", "www.microsoft.com/SqlServer/Dts")
    
    $executable = $xml.SelectSingleNode("//DTS:Executable", $ns)
    if ($executable) {
        $executable.SetAttribute("DelayValidation", 
            "www.microsoft.com/SqlServer/Dts", "True")
    }
    $xml.Save($file.FullName)
    Write-Host "Updated: $($file.Name)"
}
```

---

## Step 3 — Deploy to Target Environment (STG/PRD)

1. Open SSMS → Connect to target instance
2. Navigate to **Integration Services Catalogs** → **SSISDB**
3. Right-click target folder → **Deploy Project**
4. Select the `.ispac` file from Step 1
5. Follow deployment wizard → click **Deploy**

```sql
-- Verify deployment result
SELECT TOP 10
    operation_id,
    operation_type,
    CASE status
        WHEN 1 THEN 'Created'
        WHEN 2 THEN 'Running'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'Failed'
        WHEN 5 THEN 'Pending'
        WHEN 6 THEN 'Ended Unexpectedly'
        WHEN 7 THEN 'Succeeded'
        WHEN 9 THEN 'Completed'
    END             AS status_desc,
    start_time,
    end_time
FROM SSISDB.catalog.operations
ORDER BY start_time DESC
```

---

## Step 4 — Configure Environment Reference

After deployment, ensure the package references the correct environment:

```sql
-- Check existing environment references
SELECT
    er.reference_id,
    er.environment_name,
    er.environment_folder_name,
    er.reference_type
FROM SSISDB.catalog.environment_references er
JOIN SSISDB.catalog.projects p ON er.project_id = p.project_id
WHERE p.name = 'DummyProject'

-- Add environment reference if missing
DECLARE @ref_id BIGINT
EXEC SSISDB.catalog.create_environment_reference
    @environment_name = 'STG',
    @project_name = 'DummyProject',
    @folder_name = 'DummyFolder',
    @reference_type = 'R',
    @reference_id = @ref_id OUTPUT

SELECT @ref_id AS new_reference_id
```

---

## Step 5 — Configure Stored Procedure (if applicable)

If packages are triggered via Stored Procedure, ensure `/EnvReference` is included:

```sql
-- Example SP that calls SSIS package with environment reference
CREATE OR ALTER PROCEDURE dbo.usp_TriggerIntegration
AS
BEGIN
    DECLARE @cmd NVARCHAR(MAX)
    
    SET @cmd = 'dtexec /ISSERVER "\SSISDB\DummyFolder\DummyProject\DummyPackage.dtsx"'
        + ' /SERVER "dummy-server"'
        + ' /EnvReference 1'  -- ⚠️ Always include EnvReference!
        + ' /Par "\Package.Variables[User::Param1].Value";"DummyValue"'
    
    EXEC xp_cmdshell @cmd
END
```

> ⚠️ **Without `/EnvReference`**, the package cannot read environment variables — causing connection failures even when the environment is configured correctly.

---

## Step 6 — Test Package Execution

```sql
-- Execute package manually via T-SQL
DECLARE @execution_id BIGINT

EXEC SSISDB.catalog.create_execution
    @folder_name = N'DummyFolder',
    @project_name = N'DummyProject',
    @package_name = N'DummyPackage.dtsx',
    @execution_id = @execution_id OUTPUT

EXEC SSISDB.catalog.start_execution @execution_id

-- Check execution status
SELECT
    operation_id,
    CASE status
        WHEN 1 THEN 'Created'
        WHEN 2 THEN 'Running'
        WHEN 4 THEN 'Failed'
        WHEN 7 THEN 'Succeeded'
        WHEN 9 THEN 'Completed'
    END             AS status_desc,
    start_time,
    end_time,
    DATEDIFF(SECOND, start_time, end_time) AS duration_seconds
FROM SSISDB.catalog.executions
WHERE operation_id = @execution_id

-- Check error messages if failed
SELECT
    operation_id,
    message_time,
    message_type,
    message
FROM SSISDB.catalog.operation_messages
WHERE operation_id = @execution_id
  AND message_type = 120 -- errors only
ORDER BY message_time
```

---

## Post-Deployment Checklist

- [ ] Package deployed successfully to SSISDB
- [ ] DelayValidation = True confirmed on all packages
- [ ] Environment reference configured correctly
- [ ] EnvReference included in Stored Procedure
- [ ] Package executed successfully in target environment
- [ ] Execution logs reviewed — no errors
- [ ] SQL Agent Job updated to use new package version
- [ ] Notify team that deployment is complete

---

## 🔧 Common Issues & Solutions

### 1. Newtonsoft.Json Version Mismatch

**Error:**
Could not load file or assembly 'Newtonsoft.Json, Version=13.0.1.0'
The located assembly's manifest definition does not match the assembly reference.

**Cause:** DLL version in GAC does not match version required by the script component.

**Solution:**
```cmd
-- Step 1: Check current version in GAC
"C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\gacutil.exe" /l Newtonsoft.Json

-- Step 2: Remove existing version
"C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\gacutil.exe" /u Newtonsoft.Json

-- Step 3: Install correct version from NuGet cache
"C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\gacutil.exe" /i "C:\Users\dummy_user\.nuget\packages\newtonsoft.json\13.0.1\lib\net45\Newtonsoft.Json.dll"

-- Step 4: Verify
"C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\gacutil.exe" /l Newtonsoft.Json
```

---

### 2. NullReferenceException in Script Component

**Error:**
System.NullReferenceException: Object reference not set to an instance of an object
at ScriptMain.CreateNewOutputRows()

**Cause:** API connection or variable returning null before being accessed.

**Solution:** Add null check in script component:
```csharp
// Before accessing connection or API result
if (apiConnection == null)
    throw new Exception("Connection is null. Check Connection Manager configuration.");

// Before iterating API results
if (apiResult == null || apiResult.Tables.Count == 0)
{
    bool fireAgain = false;
    this.ComponentMetaData.FireWarning(0, "Script Component", 
        "No data returned from API.", "", 0);
    return;
}
```

---

### 3. SAP API "No Data Found" / BadRequest

**Error:**
[BadRequest] E: No Data Found

**Cause:** Invalid or empty parameter (e.g. wildcard `*`) sent to SAP API.

**Solution:** Validate parameter before building API request:
```csharp
string paramValue = Dts.Variables["User::DummyParam"].Value.ToString();

// Only add filter if value is valid
string filter = "";
if (!string.IsNullOrWhiteSpace(paramValue) && paramValue != "*")
{
    filter = $"&$filter=DummyField eq '{paramValue}'";
}

string url = $"https://dummy-sap-host/sap/opu/odata/...?$format=json{filter}";
```

---

### 4. Connection Fails After Deployment (DelayValidation)

**Error:**
DTS_E_CANNOTACQUIRECONNECTIONFROMCONNECTIONMANAGER
Login failed for user 'DOMAIN\server-machine$'

**Cause:** Package validates connection at startup before parameters are applied.

**Solution:** Set `DelayValidation = True` on all Connection Managers and Control Flow tasks (see Step 2 above).

---

### 5. Environment Variables Not Read by Package

**Error:** Package runs but uses wrong server/database (falls back to DEV config in STG).

**Cause:** `/EnvReference` not included in the Stored Procedure or execution command.

**Solution:** Always include `/EnvReference [id]` when calling package via dtexec (see Step 5 above).

---

### 6. Buffer Overflow in Data Flow

**Error:**
Value is too large to fit in the column data area

**Cause:** Source column data exceeds the defined column length in Data Flow component.

**Solution:**
1. Open Data Flow task in Visual Studio
2. Double-click the source component
3. Go to **Input and Output Properties**
4. Find the affected column → increase `Length` value
5. Rebuild and redeploy

---

### 7. TargetServerVersion Mismatch

**Error:** Package fails validation or deployment due to SQL Server version incompatibility.

**Cause:** Project `TargetServerVersion` set to wrong SQL Server version.

**Solution:**
1. Right-click project in Visual Studio → **Properties**
2. Go to **Configuration Properties**
3. Change `TargetServerVersion` to match actual server version (e.g. SQL Server 2019)
4. Rebuild and redeploy

---

## 👤 Author

**Rika Afriyani** — Junior DBA  
💼 [LinkedIn](https://linkedin.com/in/rika-afriyani-b86457191) | 🐙 [GitHub](https://github.com/Rikajo90)
