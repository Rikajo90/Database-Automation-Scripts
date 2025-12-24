# 🤖 Database Automation Scripts

Production-ready SQL Server automation scripts for backup, monitoring, and maintenance tasks. All scripts tested in real production environments.

## 📁 Script Categories

### 🔄 Backup Automation
Scripts for automated database backup and recovery

### 📊 Monitoring
Health checks and performance monitoring scripts

### 🔧 Maintenance
Index optimization and database maintenance tasks

---

## 📜 Available Scripts

### 1. ⭐ [Daily Full Backup](./backup-automation/daily_full_backup.sql)
**Purpose:** Automated full database backup with compression and verification

**Features:**
- ✅ Compression enabled (saves storage)
- ✅ Automatic backup verification
- ✅ Old backup cleanup (retention policy)
- ✅ Error handling and logging
- ✅ Backup size reporting

**Schedule:** Daily at 2:00 AM via SQL Server Agent

**Usage:**
```sql
-- Edit these variables in the script:
@DatabaseName = 'YourDatabaseName'
@BackupPath = 'D:\SQLBackups\'
@RetentionDays = 7
```

---

### 2. ⭐ [Database Health Check](./monitoring/database_health_check.sql)
**Purpose:** Comprehensive database health monitoring

**Checks:**
- ✅ Blocking sessions
- ✅ CPU usage
- ✅ Memory usage
- ✅ Database file sizes
- ✅ Last backup status
- ✅ Failed jobs (last 24 hours)
- ✅ Database corruption check (DBCC CHECKDB)

**Schedule:** Daily or on-demand

**Output:** Detailed health report with warnings

---

### 3. ⭐ [Slow Queries Report](./monitoring/slow_queries_report.sql)
**Purpose:** Identify and analyze slow-running queries

**Features:**
- ✅ Top 20 slowest queries by average execution time
- ✅ Execution count and duration
- ✅ CPU usage metrics
- ✅ Logical reads/writes
- ✅ Full query text and execution plan

**Threshold:** Queries with avg duration > 0.1 seconds

**Use Case:** Performance tuning and optimization

---

### 4. ⭐ [Index Maintenance](./maintenance/rebuild_reorg_indexes.sql)
**Purpose:** Rebuild or reorganize fragmented indexes

**Logic:**
- **Reorganize** if fragmentation 10-30%
- **Rebuild** if fragmentation > 30%
- **Skip** if fragmentation < 10%

**Features:**
- ✅ Automatic fragmentation detection
- ✅ Smart rebuild/reorganize decision
- ✅ Statistics update after maintenance
- ✅ Progress tracking and error handling
- ✅ Duration reporting

**Schedule:** Weekly (Sunday 3:00 AM)

---

## 🎯 Benefits

### ⚡ Time Savings
- Automate repetitive DBA tasks
- Reduce manual intervention
- Schedule during off-peak hours

### 🛡️ Reliability
- Proven in production environments
- Error handling and logging
- Verification and validation built-in

### 📈 Performance
- Proactive monitoring
- Early issue detection
- Optimized maintenance schedules

---

## 🚀 Quick Start

### Step 1: Download Scripts
Clone or download the scripts you need

### Step 2: Customize Variables
Edit database names, paths, and thresholds in each script

### Step 3: Test in Dev Environment
Always test scripts in development before production

### Step 4: Schedule with SQL Server Agent
Create SQL Server Agent jobs for automation

### Example: Schedule Backup Job
```sql
USE msdb;
GO

EXEC dbo.sp_add_job
    @job_name = N'Daily Full Backup',
    @enabled = 1;

EXEC sp_add_jobstep
    @job_name = N'Daily Full Backup',
    @step_name = N'Run Backup',
    @subsystem = N'TSQL',
    @command = N'-- Paste your backup script here',
    @database_name = N'master';

EXEC sp_add_schedule
    @schedule_name = N'Daily at 2 AM',
    @freq_type = 4, -- Daily
    @freq_interval = 1,
    @active_start_time = 020000; -- 2:00 AM

EXEC sp_attach_schedule
    @job_name = N'Daily Full Backup',
    @schedule_name = N'Daily at 2 AM';

EXEC sp_add_jobserver
    @job_name = N'Daily Full Backup',
    @server_name = N'(local)';
```

---

## 💡 Best Practices

1. ✅ **Test First** - Always test in dev/staging environment
2. ✅ **Backup First** - Take backup before maintenance
3. ✅ **Monitor Results** - Check logs and notifications
4. ✅ **Document Changes** - Keep track of what you've scheduled
5. ✅ **Review Regularly** - Adjust thresholds based on performance
6. ✅ **Off-Peak Hours** - Schedule heavy tasks during low activity

---

## 🛠️ Requirements

- SQL Server 2016 or higher
- sysadmin or db_owner permissions
- SQL Server Agent (for scheduling)
- Adequate disk space for backups

---

## 📚 Coming Soon

- Differential backup script
- Transaction log backup script
- Database restore automation
- Email notification integration
- PowerShell automation wrapper
- Azure SQL Database versions

---

## 👤 About

**Created by:** Rika Afriyani  
**Role:** Junior Database Administrator @ PT PLN Icon+  
**Experience:** Real production database management (Vendor Invoicing Portal)

**Skills:**
- SQL Server Administration
- Backup & Recovery
- Performance Monitoring
- Always On Availability Groups (AAG)

📧 rikajo1990@gmail.com  
💼 [LinkedIn](https://linkedin.com/in/rika-afriyani-b86457191)  
🐙 [GitHub](https://github.com/Rikajo90)

---

⭐ **Found these scripts useful? Star this repository!**

💬 **Questions or improvements?** Open an issue or reach out!

🔒 **Security Note:** Always review and customize scripts before use in production. Remove sensitive information before committing.

---
*Last updated: December 2025*
