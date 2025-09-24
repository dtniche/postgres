-- 创建测试表来验证字段映射
-- 测试不同的表类型和配置

-- 1. 创建普通表
CREATE TABLE IF NOT EXISTS test_normal_table (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- 2. 创建带fillfactor的表
CREATE TABLE IF NOT EXISTS test_fillfactor_table (
    id SERIAL PRIMARY KEY,
    name TEXT
) WITH (fillfactor=80);

-- 3. 创建临时表
CREATE TEMP TABLE test_temp_table (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- 4. 查看测试表的字段映射
SELECT 
    'TEST_TABLES_FIELD_MAPPING:' as info;

SELECT 
    table_name,
    logging,
    backed_up,
    segment_created,
    pct_free,
    pct_used,
    temporary,
    buffer_pool,
    compression
FROM dba_all_tables 
WHERE table_name LIKE 'test_%'
ORDER BY table_name;

-- 5. 查看所有表的字段值分布（包括测试表）
SELECT 
    'UPDATED_FIELD_VALUE_COUNTS:' as info;

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
UNION ALL
SELECT 
    'temporary' as field_name,
    temporary as field_value,
    COUNT(*) as count
FROM dba_all_tables 
GROUP BY temporary
ORDER BY field_name, field_value;

-- 清理测试表
DROP TABLE IF EXISTS test_normal_table;
DROP TABLE IF EXISTS test_fillfactor_table;
