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
DROP VIEW IF EXISTS dba_arguments CASCADE;
DROP VIEW IF EXISTS all_arguments CASCADE;
DROP VIEW IF EXISTS user_arguments CASCADE;
DROP VIEW IF EXISTS dba_col_privs CASCADE;
DROP VIEW IF EXISTS all_col_privs CASCADE;
DROP VIEW IF EXISTS user_col_privs CASCADE;
DROP VIEW IF EXISTS dba_col_comments CASCADE;
DROP VIEW IF EXISTS all_col_comments CASCADE;
DROP VIEW IF EXISTS user_col_comments CASCADE;
DROP FUNCTION IF EXISTS all_tables_base(boolean, boolean, boolean);
DROP FUNCTION IF EXISTS tables_base(boolean, boolean, boolean);
DROP FUNCTION IF EXISTS arguments_base(boolean, boolean, boolean);
DROP FUNCTION IF EXISTS col_privs_base(boolean, boolean, boolean);
DROP FUNCTION IF EXISTS col_comments_base(boolean, boolean, boolean);
-- 创建基础函数，用于生成所有表信息
-- 参数: include_system_tables (是否包含系统表), current_user_only (是否只包含当前用户的表)
CREATE OR REPLACE FUNCTION tables_base(
    include_system_tables boolean DEFAULT true,
    current_user_only boolean DEFAULT false,
    visible_only boolean DEFAULT false
  ) RETURNS TABLE (
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
  ) LANGUAGE sql STABLE AS $$
  SELECT -- 基本标识信息（无 owner）
    c.relname::text AS table_name,
    n.nspname::text AS tablespace_name,
    NULL::text AS cluster_name,
    NULL::text AS iot_name,
    -- 表状态信息 (6)
    CASE
      WHEN c.relkind = 'r' THEN 'VALID'
      WHEN c.relkind = 'p' THEN 'VALID'
      ELSE 'INVALID'
    END AS status,
    -- 存储参数 (7-16) - 使用 NUMERIC 类型匹配 Oracle NUMBER
    -- Oracle pct_free: 0, 10 (空闲空间百分比)
    CASE
      WHEN c.reloptions IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM unnest(c.reloptions) AS option
        WHERE option LIKE 'fillfactor=%'
      ) THEN COALESCE(
        (
          SELECT (string_to_array(option, '=')) [2]::numeric
          FROM unnest(c.reloptions) AS option
          WHERE option LIKE 'fillfactor=%'
        ),
        10::numeric
      )
      ELSE 0::numeric
    END AS pct_free,
    -- Oracle pct_used: 0, 40 (已使用空间百分比)
    CASE
      WHEN c.reloptions IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM unnest(c.reloptions) AS option
        WHERE option LIKE 'fillfactor=%'
      ) THEN COALESCE(
        (
          SELECT 100 - (string_to_array(option, '=')) [2]::numeric
          FROM unnest(c.reloptions) AS option
          WHERE option LIKE 'fillfactor=%'
        ),
        40::numeric
      )
      ELSE 0::numeric
    END AS pct_used,
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
    -- Oracle logging: 'NO', 'YES', NULL
    CASE
      WHEN c.relpersistence = 'p' THEN 'NO' -- 永久表通常不记录日志
      WHEN c.relpersistence = 't' THEN NULL -- 临时表可能为NULL
      ELSE 'YES' -- 其他情况记录日志
    END AS logging,
    -- Oracle backed_up: 只有 'N'
    'N' AS backed_up,
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
      WHEN c.reloptions IS NOT NULL
      AND 'buffer_pool=keep' = ANY(c.reloptions) THEN 'Y'
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
      WHEN c.reloptions IS NOT NULL
      AND 'buffer_pool=keep' = ANY(c.reloptions) THEN 'KEEP'
      WHEN c.reloptions IS NOT NULL
      AND 'buffer_pool=recycle' = ANY(c.reloptions) THEN 'RECYCLE'
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
      WHEN c.reloptions IS NOT NULL
      AND 'compression=true' = ANY(c.reloptions) THEN 'ENABLED'
      ELSE 'DISABLED'
    END AS compression,
    NULL::text AS compress_for,
    'N' AS dropped,
    -- 段和内存信息 (55-70) - 只保留Oracle中存在的列
    -- Oracle segment_created: 'N/A', 'NO', 'YES'
    CASE
      WHEN c.relpersistence = 't' THEN 'N/A' -- 临时表
      WHEN c.relkind = 'p' THEN 'NO' -- 分区表
      ELSE 'YES' -- 普通表
    END AS segment_created,
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
  WHERE c.relkind IN ('r', 'p') -- 只包含普通表和分区表
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
    )
    AND (
      NOT visible_only
      OR pg_get_userbyid(c.relowner) = current_user
      OR has_table_privilege(c.oid, 'SELECT')
      OR has_table_privilege(c.oid, 'INSERT')
      OR has_table_privilege(c.oid, 'UPDATE')
      OR has_table_privilege(c.oid, 'DELETE')
      OR has_table_privilege(c.oid, 'REFERENCES')
      OR has_table_privilege(c.oid, 'TRIGGER')
      OR pg_has_role(current_user, 'pg_read_all_data', 'member')
      OR pg_has_role(current_user, 'pg_write_all_data', 'member')
    );
$$;
-- 包装函数，固定参数并控制可见性与权限暴露（紧随 base 定义后）
-- remove duplicate earlier wrapper set; keep only the set below
-- (moved) 包装函数放在 col_privs_base 定义之后
-- 包装函数，固定参数并控制可见性与权限暴露
-- (duplicate wrapper set removed)
CREATE VIEW dba_tables AS
SELECT pg_get_userbyid(c.relowner) AS owner,
  b.*
FROM tables_base(true, false, false) AS b
  JOIN pg_class c ON c.relname::text = b.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
CREATE VIEW all_tables AS
SELECT pg_get_userbyid(c.relowner) AS owner,
  b.*
FROM tables_base(true, false, true) AS b
  JOIN pg_class c ON c.relname::text = b.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
-- USER_TABLES：当前用户拥有的表（与 Oracle 一致：不包含 OWNER 列）
CREATE VIEW user_tables AS
SELECT *
FROM tables_base(false, true, false);
-- 创建 ALL_TABLES 基础函数：为 DBA_ALL_TABLES/ALL_ALL_TABLES/USER_ALL_TABLES 提供统一列序（不含 owner）
CREATE OR REPLACE FUNCTION all_tables_base(
    include_system_tables boolean DEFAULT true,
    current_user_only boolean DEFAULT false,
    visible_only boolean DEFAULT false
  ) RETURNS TABLE (
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
  ) LANGUAGE sql STABLE AS $$
SELECT b.table_name,
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
FROM tables_base(
    include_system_tables,
    current_user_only,
    visible_only
  ) AS b;
$$;
-- DBA_ALL_TABLES 作为 all_tables_base 的直接投影
CREATE VIEW dba_all_tables AS
SELECT pg_get_userbyid(c.relowner) AS owner,
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
FROM all_tables_base(true, false, false) AS b
  JOIN pg_class c ON c.relname::text = b.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
CREATE VIEW all_all_tables AS
SELECT pg_get_userbyid(c.relowner) AS owner,
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
FROM all_tables_base(true, false, true) AS b
  JOIN pg_class c ON c.relname::text = b.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = b.tablespace_name;
CREATE VIEW user_all_tables AS
SELECT *
FROM all_tables_base(false, true, false);
-- 创建基础函数，用于生成所有函数参数信息
-- 参数: include_system_functions (是否包含系统函数), current_user_only (是否只包含当前用户的函数)
CREATE OR REPLACE FUNCTION arguments_base(
    include_system_functions boolean DEFAULT true,
    current_user_only boolean DEFAULT false,
    visible_only boolean DEFAULT false
  ) RETURNS TABLE (
    -- 按 Oracle DBA_ARGUMENTS 顺序（去除 owner）
    object_name text,
    package_name text,
    object_id numeric,
    overload text,
    subprogram_id numeric,
    argument_name text,
    "position" numeric,
    sequence numeric,
    data_level numeric,
    data_type text,
    defaulted text,
    default_value text,
    default_length numeric,
    in_out text,
    data_length numeric,
    data_precision numeric,
    data_scale numeric,
    radix numeric,
    character_set_name text,
    type_owner text,
    type_name text,
    type_subname text,
    type_link text,
    type_object_type text,
    pls_type text,
    char_length numeric,
    char_used text,
    origin_con_id numeric
  ) LANGUAGE plpgsql STABLE AS $$
DECLARE rec RECORD;
arg_name text;
arg_type oid;
arg_mode char;
arg_pos int;
type_name_var text;
type_len_var int;
type_type_var char;
type_mod_var int;
type_ns_var oid;
BEGIN
  -- 权限检查：如果请求DBA级别的数据（不限制为当前用户且不限制可见性），
  -- 则检查调用者是否为超级用户
  IF NOT current_user_only AND NOT visible_only THEN
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
      RAISE EXCEPTION 'permission denied for function arguments_base: DBA-level access requires superuser privileges';
    END IF;
  END IF;

  FOR rec IN
SELECT p.oid as proc_oid,
  p.proname,
  p.pronamespace,
  p.proowner,
  p.prokind,
  p.pronargs,
  p.proargnames,
  p.proargtypes,
  p.proargmodes,
  p.prorettype,
  p.proargdefaults,
  n.nspname as schema_name,
  pg_get_userbyid(p.proowner) as owner_name
FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prokind IN ('f', 'p', 'a', 'w') -- 函数、过程、聚合函数、窗口函数
  AND NOT pg_is_other_temp_schema(n.oid)
  AND (
    CASE
      WHEN include_system_functions THEN true
      ELSE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    END
  )
  AND (
    CASE
      WHEN current_user_only THEN pg_get_userbyid(p.proowner) = current_user
      ELSE true
    END
  )
  AND (
    NOT visible_only
    OR pg_get_userbyid(p.proowner) = current_user
    OR has_function_privilege(p.oid, 'EXECUTE')
  ) LOOP -- 添加返回值作为 position=0 的参数
  IF rec.prorettype != 0 THEN object_name := rec.proname;
package_name := NULL;
object_id := rec.proc_oid;
overload := '1';
subprogram_id := NULL;
argument_name := 'RETURN_VALUE';
"position" := 0;
sequence := 0;
data_level := 0;
-- 获取返回类型信息
SELECT typname,
  typlen,
  typtype,
  typtypmod,
  typnamespace INTO type_name_var,
  type_len_var,
  type_type_var,
  type_mod_var,
  type_ns_var
FROM pg_type
WHERE oid = rec.prorettype;
-- 设置返回值
data_type := COALESCE(type_name_var, 'UNKNOWN');
data_length := COALESCE(type_len_var, 0);
data_precision := CASE
  WHEN type_type_var = 'N' THEN COALESCE(type_mod_var, 0)
  ELSE NULL
END;
data_scale := CASE
  WHEN type_type_var = 'N' THEN COALESCE(type_mod_var & 65535, 0)
  ELSE NULL
END;
type_owner := (
  SELECT nspname
  FROM pg_namespace
  WHERE oid = type_ns_var
);
type_name := data_type;
type_subname := NULL;
type_link := NULL;
pls_type := data_type;
defaulted := NULL;
default_value := NULL;
default_length := NULL;
in_out := 'OUT';
-- 处理数值类型精度
IF type_type_var = 'N' THEN radix := 10;
ELSE data_precision := NULL;
data_scale := NULL;
radix := NULL;
END IF;
character_set_name := NULL;
type_object_type := NULL;
char_length := CASE
  WHEN type_type_var = 'S' THEN COALESCE(type_mod_var, 0)
  ELSE NULL
END;
char_used := CASE
  WHEN type_type_var = 'S'
  AND type_mod_var > 0 THEN 'B'
  ELSE 'C'
END;
origin_con_id := NULL;
RETURN NEXT;
END IF;
-- 处理函数参数
IF rec.proargnames IS NOT NULL
AND array_length(rec.proargnames, 1) > 0 THEN FOR arg_pos IN 1..array_length(rec.proargnames, 1) LOOP arg_name := rec.proargnames [arg_pos];
arg_type := rec.proargtypes [arg_pos];
arg_mode := COALESCE(rec.proargmodes [arg_pos], 'i');
object_name := rec.proname;
package_name := NULL;
object_id := rec.proc_oid;
overload := '1';
subprogram_id := NULL;
argument_name := COALESCE(arg_name, '');
"position" := arg_pos;
sequence := arg_pos;
data_level := 0;
-- 获取参数类型信息
SELECT typname,
  typlen,
  typtype,
  typtypmod,
  typnamespace INTO type_name_var,
  type_len_var,
  type_type_var,
  type_mod_var,
  type_ns_var
FROM pg_type
WHERE oid = arg_type;
-- 设置参数值
data_type := COALESCE(type_name_var, 'UNKNOWN');
data_length := COALESCE(type_len_var, 0);
data_precision := CASE
  WHEN type_type_var = 'N' THEN COALESCE(type_mod_var, 0)
  ELSE NULL
END;
data_scale := CASE
  WHEN type_type_var = 'N' THEN COALESCE(type_mod_var & 65535, 0)
  ELSE NULL
END;
type_owner := (
  SELECT nspname
  FROM pg_namespace
  WHERE oid = type_ns_var
);
type_name := data_type;
type_subname := NULL;
type_link := NULL;
pls_type := data_type;
defaulted := NULL;
default_value := NULL;
default_length := NULL;
CASE
  arg_mode
  WHEN 'i' THEN in_out := 'IN';
WHEN 'o' THEN in_out := 'OUT';
WHEN 'b' THEN in_out := 'IN OUT';
ELSE in_out := 'IN';
END CASE
;
-- 处理数值类型精度
IF type_type_var = 'N' THEN radix := 10;
ELSE data_precision := NULL;
data_scale := NULL;
radix := NULL;
END IF;
character_set_name := NULL;
type_object_type := NULL;
char_length := CASE
  WHEN type_type_var = 'S' THEN COALESCE(type_mod_var, 0)
  ELSE NULL
END;
char_used := CASE
  WHEN type_type_var = 'S'
  AND type_mod_var > 0 THEN 'B'
  ELSE 'C'
END;
origin_con_id := NULL;
RETURN NEXT;
END LOOP;
END IF;
END LOOP;
RETURN;
END;
$$;
-- DBA_ARGUMENTS：所有函数参数（含系统函数），DBA视图
CREATE VIEW dba_arguments AS
SELECT pg_get_userbyid(p.proowner) AS owner,
  b.*
FROM arguments_base(true, false, false) AS b
  JOIN pg_proc p ON p.oid = b.object_id::bigint::oid
  JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = b.type_owner
  OR b.type_owner = 'pg_catalog';
-- ALL_ARGUMENTS：当前用户可见的所有函数参数，包含系统函数
CREATE VIEW all_arguments AS
SELECT pg_get_userbyid(p.proowner) AS owner,
  b.*
FROM arguments_base(true, false, true) AS b
  JOIN pg_proc p ON p.oid = b.object_id::bigint::oid
  JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = b.type_owner
  OR b.type_owner = 'pg_catalog';
-- USER_ARGUMENTS：当前用户拥有的函数参数（不含owner列）
CREATE VIEW user_arguments AS
SELECT *
FROM arguments_base(false, true, false);
-- 创建基础函数，用于生成列权限信息
-- 参数: include_system_objects (是否包含系统对象), current_user_only (是否只包含当前用户的权限)
CREATE OR REPLACE FUNCTION col_privs_base(
    include_system_objects boolean DEFAULT true,
    current_user_only boolean DEFAULT false,
    visible_only boolean DEFAULT false
  ) RETURNS TABLE (
    -- 按 Oracle DBA_COL_PRIVS 顺序（去除 owner）
    grantee text,
    owner text,
    table_name text,
    column_name text,
    grantor text,
    privilege text,
    grantable text,
    common text,
    inherited text
  ) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE rec RECORD;
col_rec RECORD;
grantee_name text;
owner_name text;
table_name_var text;
column_name_var text;
grantor_name text;
privilege_var text;
grantable_var text;
common_var text;
inherited_var text;
BEGIN
  -- 权限检查：如果请求DBA级别的数据（不限制为当前用户且不限制可见性），
  -- 则检查调用者是否为超级用户
  IF NOT current_user_only AND NOT visible_only THEN
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
      RAISE EXCEPTION 'permission denied for function col_privs_base: DBA-level access requires superuser privileges';
    END IF;
  END IF;

  -- 遍历所有表和列权限
FOR rec IN
SELECT c.oid as table_oid,
  c.relname,
  c.relowner,
  n.nspname as schema_name,
  pg_get_userbyid(c.relowner) as owner_name
FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') -- 表、分区表
  AND NOT pg_is_other_temp_schema(n.oid)
  AND (
    CASE
      WHEN include_system_objects THEN true
      ELSE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    END
  )
  AND (
    CASE
      WHEN current_user_only THEN pg_get_userbyid(c.relowner) = current_user
      ELSE true
    END
  )
  AND (
    NOT visible_only
    OR pg_get_userbyid(c.relowner) = current_user
    OR has_table_privilege(c.oid, 'SELECT')
    OR has_table_privilege(c.oid, 'INSERT')
    OR has_table_privilege(c.oid, 'UPDATE')
    OR has_table_privilege(c.oid, 'DELETE')
    OR has_table_privilege(c.oid, 'REFERENCES')
    OR has_table_privilege(c.oid, 'TRIGGER')
    OR pg_has_role(current_user, 'pg_read_all_data', 'member')
    OR pg_has_role(current_user, 'pg_write_all_data', 'member')
  ) LOOP -- 遍历表的列
  FOR col_rec IN
SELECT a.attname,
  a.attnum
FROM pg_attribute a
WHERE a.attrelid = rec.table_oid
  AND a.attnum > 0
  AND NOT a.attisdropped LOOP -- 设置基本信息
  owner_name := rec.owner_name::text;
  table_name_var := rec.relname::text;
  column_name_var := col_rec.attname::text;
  -- 模拟列权限信息（PostgreSQL的列权限管理相对简单）
  -- 这里主要展示表结构，实际权限信息需要从pg_class_acl等系统表获取
  -- 模拟权限信息
  grantee_name := 'PUBLIC';
  grantor_name := rec.owner_name::text;
  privilege_var := 'SELECT';
  grantable_var := 'NO';
  common_var := 'NO';
  inherited_var := 'NO';
  -- 返回记录
  grantee := grantee_name;
  owner := owner_name;
  table_name := table_name_var;
  column_name := column_name_var;
  grantor := grantor_name;
  privilege := privilege_var;
  grantable := grantable_var;
  common := common_var;
  inherited := inherited_var;
RETURN NEXT;
END LOOP;
END LOOP;
RETURN;
END;
$$;
-- DBA_COL_PRIVS：所有列权限（含系统对象），DBA视图
CREATE VIEW dba_col_privs AS
SELECT b.grantee,
  b.owner,
  b.table_name,
  b.column_name,
  b.grantor,
  b.privilege,
  b.grantable,
  b.common,
  b.inherited
FROM col_privs_base(true, false, false) AS b;
-- ALL_COL_PRIVS：当前用户可见的所有列权限，包含系统对象
CREATE VIEW all_col_privs AS
SELECT b.grantor,
  b.grantee,
  n.nspname AS table_schema,
  b.table_name,
  b.column_name,
  b.privilege,
  b.grantable,
  b.common,
  b.inherited
FROM col_privs_base(true, false, true) AS b
  JOIN pg_class c ON c.relname::text = b.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace;
-- USER_COL_PRIVS：当前用户拥有的列权限（不含owner列）
CREATE VIEW user_col_privs AS
SELECT b.grantee,
  b.owner,
  b.table_name,
  b.column_name,
  b.grantor,
  b.privilege,
  b.grantable,
  b.common,
  b.inherited
FROM col_privs_base(false, true, false) AS b;
-- 权限：与 Oracle 行为对齐
-- dba_all_tables：默认仅拥有者（超级用户）可见，不授予 PUBLIC
-- all_all_tables/user_all_tables：授予 PUBLIC
REVOKE ALL ON dba_tables
FROM PUBLIC;
REVOKE ALL ON dba_all_tables
FROM PUBLIC;
REVOKE ALL ON dba_arguments
FROM PUBLIC;
REVOKE ALL ON dba_col_privs
FROM PUBLIC;
GRANT SELECT ON all_tables TO PUBLIC;
GRANT SELECT ON all_all_tables TO PUBLIC;
GRANT SELECT ON all_arguments TO PUBLIC;
GRANT SELECT ON all_col_privs TO PUBLIC;
GRANT SELECT ON user_tables TO PUBLIC;
GRANT SELECT ON user_all_tables TO PUBLIC;
GRANT SELECT ON user_arguments TO PUBLIC;
GRANT SELECT ON user_col_privs TO PUBLIC;

-- ========================================
-- Column Comments base and views (Oracle-style COL_COMMENTS)
-- ========================================
DROP FUNCTION IF EXISTS col_comments_base(boolean, boolean, boolean);
CREATE OR REPLACE FUNCTION col_comments_base(
    include_system_objects boolean DEFAULT true,
    current_user_only boolean DEFAULT false,
    visible_only boolean DEFAULT false
  ) RETURNS TABLE (
    owner text,
    table_name text,
    column_name text,
    comments text,
    origin_con_id numeric
  ) LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT current_user_only AND NOT visible_only THEN
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
      RAISE EXCEPTION 'permission denied for function col_comments_base: DBA-level access requires superuser privileges';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    pg_get_userbyid(c.relowner)::text AS owner,
    c.relname::text AS table_name,
    a.attname::text AS column_name,
    d.description AS comments,
    NULL::numeric AS origin_con_id
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  LEFT JOIN pg_description d ON d.objoid = c.oid AND d.classoid = 'pg_class'::regclass AND d.objsubid = a.attnum
  WHERE c.relkind IN ('r','p')
    AND NOT pg_is_other_temp_schema(n.oid)
    AND (
      CASE WHEN include_system_objects THEN true
           ELSE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') END)
    AND (
      CASE WHEN current_user_only THEN pg_get_userbyid(c.relowner) = current_user
           ELSE true END)
    AND (
      NOT visible_only
      OR pg_get_userbyid(c.relowner) = current_user
      OR has_table_privilege(c.oid, 'SELECT')
      OR has_table_privilege(c.oid, 'INSERT')
      OR has_table_privilege(c.oid, 'UPDATE')
      OR has_table_privilege(c.oid, 'DELETE')
      OR has_table_privilege(c.oid, 'REFERENCES')
      OR has_table_privilege(c.oid, 'TRIGGER')
      OR pg_has_role(current_user, 'pg_read_all_data', 'member')
      OR pg_has_role(current_user, 'pg_write_all_data', 'member')
    );
END;
$$;

CREATE VIEW dba_col_comments AS
SELECT * FROM col_comments_base(true, false, false);

CREATE VIEW all_col_comments AS
SELECT * FROM col_comments_base(true, false, true);

CREATE VIEW user_col_comments AS
SELECT table_name, column_name, comments, origin_con_id
FROM col_comments_base(false, true, false);

REVOKE ALL ON dba_col_comments FROM PUBLIC;
GRANT SELECT ON all_col_comments TO PUBLIC;
GRANT SELECT ON user_col_comments TO PUBLIC;