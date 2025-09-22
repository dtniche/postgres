-- Oracle compatibility views for PostgreSQL (Improved Numeric Types)
-- This file contains views that provide Oracle-compatible interfaces
-- with proper numeric type mapping for Oracle NUMBER types

-- Drop existing views and functions if exist
DROP VIEW IF EXISTS dba_all_tables CASCADE;
DROP VIEW IF EXISTS all_all_tables CASCADE;
DROP VIEW IF EXISTS user_all_tables CASCADE;
DROP VIEW IF EXISTS dba_tables CASCADE;
DROP VIEW IF EXISTS all_tables CASCADE;
DROP VIEW IF EXISTS user_tables CASCADE;
DROP FUNCTION IF EXISTS all_tables_base(boolean, boolean);
DROP FUNCTION IF EXISTS tables_base(boolean, boolean);

-- 创建基础函数，用于生成所有表信息
-- 参数: include_system_tables (是否包含系统表), current_user_only (是否只包含当前用户的表)
CREATE OR REPLACE FUNCTION tables_base(
    include_system_tables boolean DEFAULT true,
    current_user_only boolean DEFAULT false
)
RETURNS TABLE (
    -- 按 Oracle DBA_TABLES 顺序（去除 owner）
    table_name text,
    tablespace_name text,
    cluster_name text,
    iot_name text,
    status text,
    pct_free numeric,
    pct_used numeric,
    ini_trans numeric,
    max_trans numeric,
    initial_extent numeric,
    next_extent numeric,
    min_extents numeric,
    max_extents numeric,
    pct_increase numeric,
    freelists numeric,
    freelist_groups numeric,
    logging text,
    backed_up text,
    num_rows numeric,
    blocks numeric,
    empty_blocks numeric,
    avg_space numeric,
    chain_cnt numeric,
    avg_row_len numeric,
    avg_space_freelist_blocks numeric,
    num_freelist_blocks numeric,
    degree text,
    instances text,
    cache text,
    table_lock text,
    sample_size numeric,
    last_analyzed timestamp,
    partitioned text,
    iot_type text,
    temporary text,
    secondary text,
    nested text,
    buffer_pool text,
    flash_cache text,
    cell_flash_cache text,
    row_movement text,
    global_stats text,
    user_stats text,
    duration text,
    skip_corrupt text,
    monitoring text,
    cluster_owner text,
    dependencies text,
    compression text,
    compress_for text,
    dropped text,
    read_only text,
    segment_created text,
    result_cache text,
    clustering text,
    activity_tracking text,
    dml_timestamp text,
    has_identity text,
    container_data text,
    inmemory text,
    inmemory_priority text,
    inmemory_distribute text,
    inmemory_compression text,
    inmemory_duplicate text,
    default_collation text,
    duplicated text,
    sharded text,
    externally_sharded text,
    externally_duplicated text,
    external text,
    hybrid text,
    cellmemory text,
    containers_default text,
    container_map text,
    extended_data_link text,
    extended_data_link_map text,
    inmemory_service text,
    inmemory_service_name text,
    container_map_object text,
    memoptimize_read text,
    memoptimize_write text,
    has_sensitive_column text,
    admit_null text,
    data_link_dml_enabled text,
    logical_replication text
)
LANGUAGE sql
STABLE
AS $$
SELECT 
    -- 基本标识信息（无 owner）
    c.relname AS table_name,
    n.nspname AS tablespace_name,
    NULL::text AS cluster_name,
    NULL::text AS iot_name,
    
    -- 表状态信息 (6)
    CASE 
        WHEN c.relkind = 'r' THEN 'VALID'
        WHEN c.relkind = 'p' THEN 'VALID'
        ELSE 'INVALID'
    END AS status,
    
    -- 存储参数 (7-16) - 使用 NUMERIC 类型匹配 Oracle NUMBER
    COALESCE(
        (SELECT (string_to_array(option, '='))[2]::numeric
         FROM unnest(c.reloptions) AS option 
         WHERE (string_to_array(option, '='))[1] = 'fillfactor'), 
        100::numeric
    ) AS pct_free,
    
    NULL::numeric AS pct_used,
    NULL::numeric AS ini_trans,
    NULL::numeric AS max_trans,
    NULL::numeric AS initial_extent,
    NULL::numeric AS next_extent,
    NULL::numeric AS min_extents,
    NULL::numeric AS max_extents,
    NULL::numeric AS pct_increase,
    NULL::numeric AS freelists,
    NULL::numeric AS freelist_groups,
    
    -- 日志和备份信息 (17-18)
    CASE 
        WHEN c.relpersistence = 'p' THEN 'NO'
        ELSE 'YES'
    END AS logging,
    
    CASE 
        WHEN c.relpersistence = 'p' THEN 'N'
        ELSE 'Y'
    END AS backed_up,
    
    -- 统计信息 (19-28) - 使用 NUMERIC 类型匹配 Oracle NUMBER
    COALESCE(s.n_live_tup, 0)::numeric AS num_rows,
    COALESCE(s.n_live_tup, 0)::numeric AS blocks,
    COALESCE(s.n_dead_tup, 0)::numeric AS empty_blocks,
    0::numeric AS avg_space,
    COALESCE(s.n_tup_hot_upd, 0)::numeric AS chain_cnt,
    0::numeric AS avg_row_len,
    NULL::numeric AS avg_space_freelist_blocks,
    NULL::numeric AS num_freelist_blocks,
    NULL::text AS degree,
    NULL::text AS instances,
    
    -- 缓存和锁定信息 (29-30)
    CASE 
        WHEN c.reloptions IS NOT NULL AND 
             'buffer_pool=keep' = ANY(c.reloptions) THEN 'Y'
        ELSE 'N'
    END AS cache,
    
    'ENABLED' AS table_lock,
    
    -- 采样和分析信息 (31-32)
    COALESCE(s.n_live_tup, 0)::numeric AS sample_size,
    COALESCE(s.last_analyze, s.last_autoanalyze)::timestamp AS last_analyzed,
    
    -- 分区信息 (33-35)
    CASE 
        WHEN c.relkind = 'p' THEN 'YES'
        ELSE 'NO'
    END AS partitioned,
    
    NULL::text AS iot_type,
    
    -- 临时表信息 (38-40)
    CASE 
        WHEN c.relpersistence = 't' THEN 'Y'
        ELSE 'N'
    END AS temporary,
    
    'N' AS secondary,
    'N' AS nested,
    
    -- 存储池信息 (41-43)
    CASE 
        WHEN c.reloptions IS NOT NULL AND 
             'buffer_pool=keep' = ANY(c.reloptions) THEN 'KEEP'
        WHEN c.reloptions IS NOT NULL AND 
             'buffer_pool=recycle' = ANY(c.reloptions) THEN 'RECYCLE'
        ELSE 'DEFAULT'
    END AS buffer_pool,
    
    'N' AS flash_cache,
    'N' AS cell_flash_cache,
    
    -- 行移动和其他特性 (44-50)
    'DISABLED' AS row_movement,
    'YES' AS global_stats,
    'NO' AS user_stats,
    NULL::text AS duration,
    'N' AS skip_corrupt,
    'YES' AS monitoring,
    NULL::text AS cluster_owner,
    
    -- 依赖和压缩信息 (51-55)
    'N' AS dependencies,
    CASE 
        WHEN c.reloptions IS NOT NULL AND 
             'compression=true' = ANY(c.reloptions) THEN 'ENABLED'
        ELSE 'DISABLED'
    END AS compression,
    
    NULL::text AS compress_for,
    'N' AS dropped,
    
    -- 段和内存信息 (55-70) - 只保留Oracle中存在的列
    'YES' AS segment_created,
    'N' AS inmemory,
    NULL::text AS inmemory_priority,
    NULL::text AS inmemory_distribute,
    NULL::text AS inmemory_compression,
    NULL::text AS inmemory_duplicate,
    'N' AS external,
    'N' AS hybrid,
    NULL::text AS cellmemory,
    NULL::text AS inmemory_service,
    NULL::text AS inmemory_service_name,
    'N' AS memoptimize_read,
    'N' AS memoptimize_write,
    'N' AS has_sensitive_column,
    'N' AS logical_replication,
    -- 额外兼容列 (71-89)
    'N' AS read_only,
    'N' AS result_cache,
    'N' AS clustering,
    'N' AS activity_tracking,
    NULL::text AS dml_timestamp,
    'N' AS has_identity,
    'N' AS container_data,
    NULL::text AS default_collation,
    'N' AS duplicated,
    'N' AS sharded,
    'N' AS externally_sharded,
    'N' AS externally_duplicated,
    'N' AS containers_default,
    NULL::text AS container_map,
    NULL::text AS extended_data_link,
    NULL::text AS extended_data_link_map,
    NULL::text AS container_map_object,
    'N' AS admit_null,
    'N' AS data_link_dml_enabled

FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
LEFT JOIN pg_stat_all_tables s ON s.relid = c.oid
WHERE c.relkind IN ('r', 'p')  -- 只包含普通表和分区表
  AND NOT pg_is_other_temp_schema(n.oid)
  AND (
    CASE 
      WHEN include_system_tables THEN true
      ELSE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    END
  )
  AND (
    CASE 
      WHEN current_user_only THEN pg_get_userbyid(c.relowner) = current_user
      ELSE true
    END
  );
$$;

CREATE VIEW dba_tables AS
SELECT 
  pg_get_userbyid(c.relowner) AS owner,
  b.*
FROM tables_base(true, false) AS b
JOIN pg_class c ON c.relname = b.table_name
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;

CREATE VIEW all_tables AS
SELECT 
  pg_get_userbyid(c.relowner) AS owner,
  b.*
FROM tables_base(true, false) AS b
JOIN pg_class c ON c.relname = b.table_name
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;

-- USER_TABLES：当前用户拥有的表（与 Oracle 一致：不包含 OWNER 列）
CREATE VIEW user_tables AS
SELECT * FROM tables_base(false, true);

-- 创建 ALL_TABLES 基础函数：为 DBA_ALL_TABLES/ALL_ALL_TABLES/USER_ALL_TABLES 提供统一列序（不含 owner）
CREATE OR REPLACE FUNCTION all_tables_base(
    include_system_tables boolean DEFAULT true,
    current_user_only boolean DEFAULT false
)
RETURNS TABLE (
  table_name text,
  tablespace_name text,
  cluster_name text,
  iot_name text,
  status text,
  pct_free numeric,
  pct_used numeric,
  ini_trans numeric,
  max_trans numeric,
  initial_extent numeric,
  next_extent numeric,
  min_extents numeric,
  max_extents numeric,
  pct_increase numeric,
  freelists numeric,
  freelist_groups numeric,
  logging text,
  backed_up text,
  num_rows numeric,
  blocks numeric,
  empty_blocks numeric,
  avg_space numeric,
  chain_cnt numeric,
  avg_row_len numeric,
  avg_space_freelist_blocks numeric,
  num_freelist_blocks numeric,
  degree text,
  instances text,
  cache text,
  table_lock text,
  sample_size numeric,
  last_analyzed timestamp,
  partitioned text,
  iot_type text,
  object_id_type text,
  table_type_owner text,
  table_type text,
  temporary text,
  secondary text,
  nested text,
  buffer_pool text,
  flash_cache text,
  cell_flash_cache text,
  row_movement text,
  global_stats text,
  user_stats text,
  duration text,
  skip_corrupt text,
  monitoring text,
  cluster_owner text,
  dependencies text,
  compression text,
  compress_for text,
  dropped text,
  segment_created text,
  inmemory text,
  inmemory_priority text,
  inmemory_distribute text,
  inmemory_compression text,
  inmemory_duplicate text,
  external text,
  hybrid text,
  cellmemory text,
  inmemory_service text,
  inmemory_service_name text,
  memoptimize_read text,
  memoptimize_write text,
  has_sensitive_column text,
  logical_replication text
)
LANGUAGE sql
STABLE
AS $$
SELECT 
  b.table_name,
  b.tablespace_name,
  b.cluster_name,
  b.iot_name,
  b.status,
  b.pct_free,
  b.pct_used,
  b.ini_trans,
  b.max_trans,
  b.initial_extent,
  b.next_extent,
  b.min_extents,
  b.max_extents,
  b.pct_increase,
  b.freelists,
  b.freelist_groups,
  b.logging,
  b.backed_up,
  b.num_rows,
  b.blocks,
  b.empty_blocks,
  b.avg_space,
  b.chain_cnt,
  b.avg_row_len,
  b.avg_space_freelist_blocks,
  b.num_freelist_blocks,
  b.degree,
  b.instances,
  b.cache,
  b.table_lock,
  b.sample_size,
  b.last_analyzed,
  b.partitioned,
  b.iot_type,
  NULL::text AS object_id_type,
  NULL::text AS table_type_owner,
  NULL::text AS table_type,
  b.temporary,
  b.secondary,
  b.nested,
  b.buffer_pool,
  b.flash_cache,
  b.cell_flash_cache,
  b.row_movement,
  b.global_stats,
  b.user_stats,
  b.duration,
  b.skip_corrupt,
  b.monitoring,
  b.cluster_owner,
  b.dependencies,
  b.compression,
  b.compress_for,
  b.dropped,
  b.segment_created,
  b.inmemory,
  b.inmemory_priority,
  b.inmemory_distribute,
  b.inmemory_compression,
  b.inmemory_duplicate,
  b.external,
  b.hybrid,
  b.cellmemory,
  b.inmemory_service,
  b.inmemory_service_name,
  b.memoptimize_read,
  b.memoptimize_write,
  b.has_sensitive_column,
  b.logical_replication
FROM tables_base(include_system_tables, current_user_only) AS b;
$$;

-- DBA_ALL_TABLES 作为 all_tables_base 的直接投影
CREATE VIEW dba_all_tables AS 
SELECT 
  pg_get_userbyid(c.relowner) AS owner,
  b.table_name,
  b.tablespace_name,
  b.cluster_name,
  b.iot_name,
  b.status,
  b.pct_free,
  b.pct_used,
  b.ini_trans,
  b.max_trans,
  b.initial_extent,
  b.next_extent,
  b.min_extents,
  b.max_extents,
  b.pct_increase,
  b.freelists,
  b.freelist_groups,
  b.logging,
  b.backed_up,
  b.num_rows,
  b.blocks,
  b.empty_blocks,
  b.avg_space,
  b.chain_cnt,
  b.avg_row_len,
  b.avg_space_freelist_blocks,
  b.num_freelist_blocks,
  b.degree,
  b.instances,
  b.cache,
  b.table_lock,
  b.sample_size,
  b.last_analyzed,
  b.partitioned,
  b.iot_type,
  b.object_id_type,
  b.table_type_owner,
  b.table_type,
  b.temporary,
  b.secondary,
  b.nested,
  b.buffer_pool,
  b.flash_cache,
  b.cell_flash_cache,
  b.row_movement,
  b.global_stats,
  b.user_stats,
  b.duration,
  b.skip_corrupt,
  b.monitoring,
  b.cluster_owner,
  b.dependencies,
  b.compression,
  b.compress_for,
  b.dropped,
  b.segment_created,
  b.inmemory,
  b.inmemory_priority,
  b.inmemory_distribute,
  b.inmemory_compression,
  b.inmemory_duplicate,
  b.external,
  b.hybrid,
  b.cellmemory,
  b.inmemory_service,
  b.inmemory_service_name,
  b.memoptimize_read,
  b.memoptimize_write,
  b.has_sensitive_column,
  b.logical_replication
FROM all_tables_base(true, false) AS b
JOIN pg_class c ON c.relname = b.table_name
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
CREATE VIEW all_all_tables AS 
SELECT 
  pg_get_userbyid(c.relowner) AS owner,
  b.table_name,
  b.tablespace_name,
  b.cluster_name,
  b.iot_name,
  b.status,
  b.pct_free,
  b.pct_used,
  b.ini_trans,
  b.max_trans,
  b.initial_extent,
  b.next_extent,
  b.min_extents,
  b.max_extents,
  b.pct_increase,
  b.freelists,
  b.freelist_groups,
  b.logging,
  b.backed_up,
  b.num_rows,
  b.blocks,
  b.empty_blocks,
  b.avg_space,
  b.chain_cnt,
  b.avg_row_len,
  b.avg_space_freelist_blocks,
  b.num_freelist_blocks,
  b.degree,
  b.instances,
  b.cache,
  b.table_lock,
  b.sample_size,
  b.last_analyzed,
  b.partitioned,
  b.iot_type,
  b.object_id_type,
  b.table_type_owner,
  b.table_type,
  b.temporary,
  b.secondary,
  b.nested,
  b.buffer_pool,
  b.flash_cache,
  b.cell_flash_cache,
  b.row_movement,
  b.global_stats,
  b.user_stats,
  b.duration,
  b.skip_corrupt,
  b.monitoring,
  b.cluster_owner,
  b.dependencies,
  b.compression,
  b.compress_for,
  b.dropped,
  b.segment_created,
  b.inmemory,
  b.inmemory_priority,
  b.inmemory_distribute,
  b.inmemory_compression,
  b.inmemory_duplicate,
  b.external,
  b.hybrid,
  b.cellmemory,
  b.inmemory_service,
  b.inmemory_service_name,
  b.memoptimize_read,
  b.memoptimize_write,
  b.has_sensitive_column,
  b.logical_replication
FROM all_tables_base(true, false) AS b
JOIN pg_class c ON c.relname = b.table_name
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
CREATE VIEW user_all_tables AS SELECT * FROM all_tables_base(false, true);

-- 权限：与 Oracle 行为对齐
-- dba_all_tables：默认仅拥有者（超级用户）可见，不授予 PUBLIC
-- all_all_tables/user_all_tables：授予 PUBLIC
REVOKE ALL ON dba_tables FROM PUBLIC;
REVOKE ALL ON dba_all_tables FROM PUBLIC;
GRANT SELECT ON all_tables TO PUBLIC;
GRANT SELECT ON all_all_tables TO PUBLIC;
GRANT SELECT ON user_tables TO PUBLIC;
GRANT SELECT ON user_all_tables TO PUBLIC;
