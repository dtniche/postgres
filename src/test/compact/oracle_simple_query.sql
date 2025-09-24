-- 简化的Oracle字段值查询
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF

-- 1. 查看关键字段的实际值
SELECT 'STATUS_VALUES:' FROM dual;
SELECT DISTINCT status FROM dba_all_tables ORDER BY status;

SELECT 'LOGGING_VALUES:' FROM dual;
SELECT DISTINCT logging FROM dba_all_tables ORDER BY logging;

SELECT 'BACKED_UP_VALUES:' FROM dual;
SELECT DISTINCT backed_up FROM dba_all_tables ORDER BY backed_up;

SELECT 'TEMPORARY_VALUES:' FROM dual;
SELECT DISTINCT temporary FROM dba_all_tables ORDER BY temporary;

SELECT 'BUFFER_POOL_VALUES:' FROM dual;
SELECT DISTINCT buffer_pool FROM dba_all_tables ORDER BY buffer_pool;

SELECT 'COMPRESSION_VALUES:' FROM dual;
SELECT DISTINCT compression FROM dba_all_tables ORDER BY compression;

SELECT 'PARTITIONED_VALUES:' FROM dual;
SELECT DISTINCT partitioned FROM dba_all_tables ORDER BY partitioned;

SELECT 'INMEMORY_VALUES:' FROM dual;
SELECT DISTINCT inmemory FROM dba_all_tables ORDER BY inmemory;

SELECT 'EXTERNAL_VALUES:' FROM dual;
SELECT DISTINCT external FROM dba_all_tables ORDER BY external;

SELECT 'SEGMENT_CREATED_VALUES:' FROM dual;
SELECT DISTINCT segment_created FROM dba_all_tables ORDER BY segment_created;

SELECT 'GLOBAL_STATS_VALUES:' FROM dual;
SELECT DISTINCT global_stats FROM dba_all_tables ORDER BY global_stats;

SELECT 'USER_STATS_VALUES:' FROM dual;
SELECT DISTINCT user_stats FROM dba_all_tables ORDER BY user_stats;

SELECT 'MONITORING_VALUES:' FROM dual;
SELECT DISTINCT monitoring FROM dba_all_tables ORDER BY monitoring;

SELECT 'ROW_MOVEMENT_VALUES:' FROM dual;
SELECT DISTINCT row_movement FROM dba_all_tables ORDER BY row_movement;

-- 2. 查看一些样本数据
SELECT 'SAMPLE_DATA:' FROM dual;
SELECT owner||'|'||table_name||'|'||tablespace_name||'|'||status||'|'||logging||'|'||backed_up||'|'||temporary||'|'||buffer_pool||'|'||compression||'|'||partitioned||'|'||inmemory||'|'||external||'|'||segment_created||'|'||global_stats||'|'||user_stats||'|'||monitoring||'|'||row_movement
FROM dba_all_tables 
WHERE rownum <= 10
ORDER BY owner, table_name;

EXIT;
