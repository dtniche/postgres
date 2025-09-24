-- 测试修正后的PostgreSQL字段映射
-- 对比Oracle实际数据

-- 1. 查看关键字段的值分布
SELECT 'LOGGING_VALUES:' as field_name;
SELECT DISTINCT logging FROM dba_all_tables ORDER BY logging;

SELECT 'BACKED_UP_VALUES:' as field_name;
SELECT DISTINCT backed_up FROM dba_all_tables ORDER BY backed_up;

SELECT 'SEGMENT_CREATED_VALUES:' as field_name;
SELECT DISTINCT segment_created FROM dba_all_tables ORDER BY segment_created;

SELECT 'PCT_FREE_VALUES:' as field_name;
SELECT DISTINCT pct_free FROM dba_all_tables ORDER BY pct_free;

SELECT 'PCT_USED_VALUES:' as field_name;
SELECT DISTINCT pct_used FROM dba_all_tables ORDER BY pct_used;

-- 2. 查看样本数据
SELECT 'SAMPLE_DATA:' as info;
SELECT 
    owner, table_name, tablespace_name, status, logging, backed_up,
    temporary, buffer_pool, compression, partitioned, inmemory, external,
    segment_created, global_stats, user_stats, monitoring, row_movement,
    pct_free, pct_used
FROM dba_all_tables 
WHERE table_name IN ('pg_class', 'pg_attribute', 'pg_type')
ORDER BY owner, table_name
LIMIT 5;

-- 3. 统计各字段的值分布
SELECT 'FIELD_VALUE_COUNTS:' as info;
SELECT 
    'logging' as field_name,
    logging as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY logging
UNION ALL
SELECT 
    'backed_up' as field_name,
    backed_up as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY backed_up
UNION ALL
SELECT 
    'segment_created' as field_name,
    segment_created as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY segment_created
UNION ALL
SELECT 
    'pct_free' as field_name,
    pct_free::text as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY pct_free
UNION ALL
SELECT 
    'pct_used' as field_name,
    pct_used::text as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY pct_used
ORDER BY field_name, field_value;
