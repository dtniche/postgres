-- Oracle DBA_ALL_TABLES 字段内容分析脚本
-- 用于对比PostgreSQL实现与Oracle实际数据的差异

-- 1. 查看Oracle DBA_ALL_TABLES的基本信息
SELECT 
    owner,
    table_name,
    tablespace_name,
    status,
    logging,
    backed_up,
    num_rows,
    blocks,
    partitioned,
    temporary,
    buffer_pool,
    compression,
    segment_created,
    inmemory,
    external
FROM dba_all_tables 
WHERE rownum <= 5
ORDER BY owner, table_name;

-- 2. 查看Oracle中不同状态值的分布
SELECT 
    status,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY status
ORDER BY status;

-- 3. 查看Oracle中logging字段的值分布
SELECT 
    logging,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY logging
ORDER BY logging;

-- 4. 查看Oracle中backed_up字段的值分布
SELECT 
    backed_up,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY backed_up
ORDER BY backed_up;

-- 5. 查看Oracle中temporary字段的值分布
SELECT 
    temporary,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY temporary
ORDER BY temporary;

-- 6. 查看Oracle中buffer_pool字段的值分布
SELECT 
    buffer_pool,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY buffer_pool
ORDER BY buffer_pool;

-- 7. 查看Oracle中compression字段的值分布
SELECT 
    compression,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY compression
ORDER BY compression;

-- 8. 查看Oracle中partitioned字段的值分布
SELECT 
    partitioned,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY partitioned
ORDER BY partitioned;

-- 9. 查看Oracle中inmemory字段的值分布
SELECT 
    inmemory,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY inmemory
ORDER BY inmemory;

-- 10. 查看Oracle中external字段的值分布
SELECT 
    external,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY external
ORDER BY external;

-- 11. 查看Oracle中segment_created字段的值分布
SELECT 
    segment_created,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY segment_created
ORDER BY segment_created;

-- 12. 查看Oracle中一些关键字段的实际值
SELECT 
    owner,
    table_name,
    tablespace_name,
    status,
    logging,
    backed_up,
    num_rows,
    blocks,
    partitioned,
    temporary,
    buffer_pool,
    compression,
    segment_created,
    inmemory,
    external,
    global_stats,
    user_stats,
    monitoring,
    row_movement
FROM dba_all_tables 
WHERE owner IN ('SYS', 'SYSTEM', 'HR')
  AND rownum <= 10
ORDER BY owner, table_name;

-- 13. 查看Oracle中NULL值的分布
SELECT 
    COUNT(*) as total_tables,
    COUNT(tablespace_name) as tablespace_name_not_null,
    COUNT(cluster_name) as cluster_name_not_null,
    COUNT(iot_name) as iot_name_not_null,
    COUNT(pct_used) as pct_used_not_null,
    COUNT(ini_trans) as ini_trans_not_null,
    COUNT(max_trans) as max_trans_not_null,
    COUNT(initial_extent) as initial_extent_not_null,
    COUNT(next_extent) as next_extent_not_null,
    COUNT(min_extents) as min_extents_not_null,
    COUNT(max_extents) as max_extents_not_null,
    COUNT(pct_increase) as pct_increase_not_null,
    COUNT(freelists) as freelists_not_null,
    COUNT(freelist_groups) as freelist_groups_not_null
FROM dba_all_tables;

-- 14. 查看Oracle中一些数值字段的统计信息
SELECT 
    MIN(num_rows) as min_num_rows,
    MAX(num_rows) as max_num_rows,
    AVG(num_rows) as avg_num_rows,
    MIN(blocks) as min_blocks,
    MAX(blocks) as max_blocks,
    AVG(blocks) as avg_blocks
FROM dba_all_tables 
WHERE num_rows IS NOT NULL AND blocks IS NOT NULL;

-- 15. 查看Oracle中tablespace_name的实际值
SELECT DISTINCT tablespace_name
FROM dba_all_tables 
ORDER BY tablespace_name;
