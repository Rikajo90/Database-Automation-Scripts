-- =============================================
-- Daily Full Database Backup Script
-- Author: Rika Afriyani
-- Purpose: Automated full backup with compression and verification
-- Schedule: Daily at 2:00 AM via SQL Server Agent
-- =============================================

USE master;
GO

DECLARE @BackupPath NVARCHAR(500);
DECLARE @DatabaseName NVARCHAR(100) = 'ProductionDB'; -- Change to your DB name
DECLARE @FileName NVARCHAR(500);
DECLARE @Date NVARCHAR(20);
DECLARE @RetentionDays INT = 7; -- Keep backups for 7 days

-- Generate filename with timestamp
SET @Date = CONVERT(NVARCHAR(20), GETDATE(), 112) + '_' + 
            REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 108), ':', '');
SET @BackupPath = 'D:\SQLBackups\'; -- Change to your backup path
SET @FileName = @BackupPath + @DatabaseName + '_Full_' + @Date + '.bak';

PRINT '========================================';
PRINT 'Starting Full Backup: ' + @DatabaseName;
PRINT 'Timestamp: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '========================================';

BEGIN TRY
    -- Perform full backup with compression
    BACKUP DATABASE @DatabaseName
    TO DISK = @FileName
    WITH 
        COMPRESSION,
        INIT,
        NAME = @DatabaseName + ' Full Backup',
        DESCRIPTION = 'Automated daily full backup',
        STATS = 10,
        CHECKSUM;
    
    PRINT 'Backup completed successfully: ' + @FileName;
    
    -- Verify backup integrity
    PRINT 'Verifying backup integrity...';
    RESTORE VERIFYONLY FROM DISK = @FileName;
    PRINT 'Backup verification successful!';
    
    -- Get backup size
    DECLARE @BackupSizeMB DECIMAL(10,2);
    SELECT @BackupSizeMB = CAST(backup_size/1024/1024 AS DECIMAL(10,2))
    FROM msdb.dbo.backupset
    WHERE database_name = @DatabaseName
    AND type = 'D'
    AND backup_finish_date = (
        SELECT MAX(backup_finish_date)
        FROM msdb.dbo.backupset
        WHERE database_name = @DatabaseName AND type = 'D'
    );
    
    PRINT 'Backup size: ' + CAST(@BackupSizeMB AS VARCHAR(20)) + ' MB';
    
    -- Cleanup old backups
    PRINT 'Cleaning up backups older than ' + CAST(@RetentionDays AS VARCHAR(5)) + ' days...';
    DECLARE @CleanupDate DATETIME = DATEADD(DAY, -@RetentionDays, GETDATE());
    
    EXECUTE master.dbo.xp_delete_file 0, @BackupPath, N'bak', @CleanupDate;
    PRINT 'Old backups cleaned up successfully.';
    
    PRINT '========================================';
    PRINT 'Backup process completed successfully!';
    PRINT '========================================';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: ' + ERROR_MESSAGE();
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
    PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
    
    -- Send alert or log error here
    RAISERROR('Backup failed! Check error log.', 16, 1);
END CATCH;
GO
