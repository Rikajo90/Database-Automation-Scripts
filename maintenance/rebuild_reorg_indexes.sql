-- =============================================
-- Index Maintenance Script
-- Author: Rika Afriyani
-- Purpose: Rebuild or reorganize fragmented indexes
-- Schedule: Weekly (Sunday 3:00 AM)
-- =============================================

USE master;
GO

SET NOCOUNT ON;

DECLARE @DatabaseName NVARCHAR(128) = DB_NAME(); -- Current database
DECLARE @FragmentationThresholdReorg DECIMAL(5,2) = 10.0; -- Reorganize if > 10%
DECLARE @FragmentationThresholdRebuild DECIMAL(5,2) = 30.0; -- Rebuild if > 30%

PRINT '============================================';
PRINT 'INDEX MAINTENANCE STARTED';
PRINT 'Database: ' + @DatabaseName;
PRINT 'Date: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '============================================';
PRINT '';

-- Create temp table for fragmented indexes
CREATE TABLE #FragmentedIndexes (
    DatabaseName NVARCHAR(128),
    SchemaName NVARCHAR(128),
    TableName NVARCHAR(128),
    IndexName NVARCHAR(128),
    FragmentationPercent DECIMAL(5,2),
    PageCount BIGINT,
    Action VARCHAR(20)
);

-- Get fragmented indexes
INSERT INTO #FragmentedIndexes
SELECT 
    DB_NAME() AS DatabaseName,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent AS FragmentationPercent,
    ips.page_count AS PageCount,
    CASE 
        WHEN ips.avg_fragmentation_in_percent >= @FragmentationThresholdRebuild THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= @FragmentationThresholdReorg THEN 'REORGANIZE'
        ELSE 'SKIP'
    END AS Action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.objects o ON i.object_id = o.object_id
WHERE ips.avg_fragmentation_in_percent > @FragmentationThresholdReorg
    AND ips.page_count > 100 -- Skip small indexes
    AND i.name IS NOT NULL
    AND o.type = 'U' -- User tables only
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Show fragmented indexes
PRINT 'FRAGMENTED INDEXES FOUND:';
PRINT '-------------------------------------------';
SELECT * FROM #FragmentedIndexes ORDER BY FragmentationPercent DESC;
PRINT '';

-- Perform maintenance
DECLARE @SchemaName NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);
DECLARE @IndexName NVARCHAR(128);
DECLARE @Action VARCHAR(20);
DECLARE @SQL NVARCHAR(MAX);
DECLARE @StartTime DATETIME;
DECLARE @EndTime DATETIME;

DECLARE index_cursor CURSOR FOR
    SELECT SchemaName, TableName, IndexName, Action
    FROM #FragmentedIndexes
    WHERE Action IN ('REBUILD', 'REORGANIZE');

OPEN index_cursor;
FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @Action;

PRINT 'PERFORMING INDEX MAINTENANCE:';
PRINT '-------------------------------------------';

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @StartTime = GETDATE();
    
    BEGIN TRY
        IF @Action = 'REBUILD'
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REBUILD WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON)';
            EXEC sp_executesql @SQL;
            
            SET @EndTime = GETDATE();
            PRINT '✓ REBUILT: ' + @SchemaName + '.' + @TableName + '.' + @IndexName + ' (Duration: ' + 
                  CAST(DATEDIFF(SECOND, @StartTime, @EndTime) AS VARCHAR(10)) + 's)';
        END
        ELSE IF @Action = 'REORGANIZE'
        BEGIN
            SET @SQL = 'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REORGANIZE';
            EXEC sp_executesql @SQL;
            
            SET @EndTime = GETDATE();
            PRINT '✓ REORGANIZED: ' + @SchemaName + '.' + @TableName + '.' + @IndexName + ' (Duration: ' + 
                  CAST(DATEDIFF(SECOND, @StartTime, @EndTime) AS VARCHAR(10)) + 's)';
        END
    END TRY
    BEGIN CATCH
        PRINT '⚠️ ERROR: ' + @SchemaName + '.' + @TableName + '.' + @IndexName;
        PRINT '   Error: ' + ERROR_MESSAGE();
    END CATCH
    
    FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @Action;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;

-- Update statistics
PRINT '';
PRINT 'UPDATING STATISTICS...';
EXEC sp_updatestats;
PRINT '✓ Statistics updated';

-- Cleanup
DROP TABLE #FragmentedIndexes;

PRINT '';
PRINT '============================================';
PRINT 'INDEX MAINTENANCE COMPLETED';
PRINT 'Time: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '============================================';
