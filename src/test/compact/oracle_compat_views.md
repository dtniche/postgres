### Oracle 兼容视图设计（oracle_compat_views.sql）

#### 设计目标
- 提供与 Oracle DBA_ALL_TABLES / ALL_TABLES / USER_TABLES 等价的只读视图接口。
- 字段集合、名称与含义尽可能模拟 Oracle；数值型统一 NUMERIC，时间使用 TIMESTAMP（无时区），其他采用 TEXT。
- 可见性与权限模型贴近 Oracle：普通用户可用 ALL/USER 视图，不可用 DBA 视图。

#### 视图与权限
- dba_all_tables
  - 含义：所有表（含系统对象），DBA 视图
  - 实现：`SELECT * FROM dba_all_tables_base(true, false)`
  - 权限：不授予 PUBLIC（`REVOKE ALL ON dba_all_tables FROM PUBLIC`）

- all_all_tables
  - 含义：当前用户可见的所有表，包含系统对象（模拟 Oracle ALL_TABLES）
  - 实现：`SELECT * FROM dba_all_tables_base(true, false)`
  - 权限：`GRANT SELECT ON all_all_tables TO PUBLIC`

- user_all_tables
  - 含义：当前用户拥有的表
  - 实现：`SELECT * FROM dba_all_tables_base(false, true)`
  - 权限：`GRANT SELECT ON user_all_tables TO PUBLIC`

#### 数据来源与过滤
- 主来源：
  - `pg_class c`（表/分区表：`relkind in ('r','p')`）
  - `pg_namespace n`（schema）
  - `pg_tablespace t`（可选）
  - `pg_stat_all_tables s`（统计）
- 过滤：
  - 排除其他临时 schema：`NOT pg_is_other_temp_schema(n.oid)`
  - 是否包含系统对象：
    - 包含：不过滤系统 schema
    - 排除：排除 `pg_catalog`, `information_schema`, `pg_toast`
  - 仅当前用户：`pg_get_userbyid(c.relowner) = current_user`

#### 列映射表（70 列）
以下表格列出 Oracle DBA_ALL_TABLES 的列映射，PostgreSQL 实现完全匹配 Oracle 的70列结构。

| 序 | Oracle 含义 | 列名 | 类型 | 来源/规则 | 说明 |
|----|-------------|------|------|-----------|------|
| 1 | 所有者 | owner | text | `pg_get_userbyid(c.relowner)` | 表 owner 名称 |
| 2 | 表名 | table_name | text | `c.relname` | |
| 3 | 表空间名 | tablespace_name | text | `n.nspname` | 语义上更接近 schema 名；保持兼容输出字段名 |
| 4 | 集群名 | cluster_name | text | `NULL` | Oracle 相关，无直接映射 |
| 5 | IOT 名 | iot_name | text | `NULL` | 无直接映射 |
| 6 | 状态 | status | text | `CASE c.relkind IN ('r','p') THEN 'VALID' ELSE 'INVALID' END` | |
| 7 | PCT_FREE | pct_free | numeric | 从 `reloptions` 中解析 `fillfactor`，默认 100 | 数值统一 numeric |
| 8 | PCT_USED | pct_used | numeric | `NULL` | |
| 9 | INITRANS | ini_trans | numeric | `NULL` | |
| 10 | MAXTRANS | max_trans | numeric | `NULL` | |
| 11 | INITIAL_EXTENT | initial_extent | numeric | `NULL` | |
| 12 | NEXT_EXTENT | next_extent | numeric | `NULL` | |
| 13 | MIN_EXTENTS | min_extents | numeric | `NULL` | |
| 14 | MAX_EXTENTS | max_extents | numeric | `NULL` | |
| 15 | PCT_INCREASE | pct_increase | numeric | `NULL` | |
| 16 | FREELISTS | freelists | numeric | `NULL` | |
| 17 | FREELIST_GROUPS | freelist_groups | numeric | `NULL` | |
| 18 | LOGGING | logging | text | `relpersistence='p' → 'NO' ELSE 'YES'` | |
| 19 | BACKED_UP | backed_up | text | `relpersistence='p' → 'N' ELSE 'Y'` | |
| 20 | NUM_ROWS | num_rows | numeric | `COALESCE(s.n_live_tup,0)` | 统计估计值 |
| 21 | BLOCKS | blocks | numeric | `COALESCE(s.n_live_tup,0)` | 近似占位，兼容列 |
| 22 | EMPTY_BLOCKS | empty_blocks | numeric | `COALESCE(s.n_dead_tup,0)` | |
| 23 | AVG_SPACE | avg_space | numeric | 常量 0 | |
| 24 | CHAIN_CNT | chain_cnt | numeric | `COALESCE(s.n_tup_hot_upd,0)` | |
| 25 | AVG_ROW_LEN | avg_row_len | numeric | 常量 0 | |
| 26 | AVG_SPACE_FREELIST_BLOCKS | avg_space_freelist_blocks | numeric | `NULL` | |
| 27 | NUM_FREELIST_BLOCKS | num_freelist_blocks | numeric | `NULL` | |
| 28 | DEGREE | degree | numeric | `NULL` | 并行度占位 |
| 29 | INSTANCES | instances | numeric | `NULL` | |
| 30 | CACHE | cache | text | `reloptions` 包含 `buffer_pool=keep` → 'Y' ELSE 'N' | |
| 31 | TABLE_LOCK | table_lock | text | 常量 'ENABLED' | |
| 32 | SAMPLE_SIZE | sample_size | numeric | `COALESCE(s.n_live_tup,0)` | |
| 33 | LAST_ANALYZED | last_analyzed | timestamp | `COALESCE(s.last_analyze, s.last_autoanalyze)` | 无时区 |
| 34 | PARTITIONED | partitioned | text | `relkind='p' → 'YES' ELSE 'NO'` | |
| 35 | IOT_TYPE | iot_type | text | `NULL` | |
| 36 | OBJECT_ID_TYPE | object_id_type | text | `NULL` | |
| 37 | TABLE_TYPE_OWNER | table_type_owner | text | `NULL` | |
| 38 | TABLE_TYPE | table_type | text | `NULL` | |
| 39 | TEMPORARY | temporary | text | `relpersistence='t' → 'Y' ELSE 'N'` | |
| 40 | SECONDARY | secondary | text | 常量 'N' | |
| 41 | NESTED | nested | text | 常量 'N' | |
| 42 | BUFFER_POOL | buffer_pool | text | `reloptions`：keep/recycle/默认 | |
| 43 | FLASH_CACHE | flash_cache | text | 常量 'N' | |
| 44 | CELL_FLASH_CACHE | cell_flash_cache | text | 常量 'N' | |
| 45 | ROW_MOVEMENT | row_movement | text | 常量 'DISABLED' | |
| 46 | GLOBAL_STATS | global_stats | text | 常量 'YES' | |
| 47 | USER_STATS | user_stats | text | 常量 'NO' | |
| 48 | DURATION | duration | text | `NULL` | |
| 49 | SKIP_CORRUPT | skip_corrupt | text | 常量 'N' | |
| 50 | MONITORING | monitoring | text | 常量 'YES' | |
| 51 | CLUSTER_OWNER | cluster_owner | text | `NULL` | |
| 52 | DEPENDENCIES | dependencies | text | 常量 'N' | |
| 53 | COMPRESSION | compression | text | `reloptions` 含 `compression=true` → 'ENABLED' ELSE 'DISABLED' | |
| 54 | COMPRESS_FOR | compress_for | text | `NULL` | |
| 55 | DROPPED | dropped | text | 常量 'N' | |
| 56 | SEGMENT_CREATED | segment_created | text | 常量 'YES' | |
| 57 | INMEMORY | inmemory | text | 常量 'N' | |
| 58 | INMEMORY_PRIORITY | inmemory_priority | text | `NULL` | |
| 59 | INMEMORY_DISTRIBUTE | inmemory_distribute | text | `NULL` | |
| 60 | INMEMORY_COMPRESSION | inmemory_compression | text | `NULL` | |
| 61 | INMEMORY_DUPLICATE | inmemory_duplicate | text | `NULL` | |
| 62 | EXTERNAL | external | text | 常量 'N' | |
| 63 | HYBRID | hybrid | text | 常量 'N' | |
| 64 | CELLMEMORY | cellmemory | text | `NULL` | |
| 65 | INMEMORY_SERVICE | inmemory_service | text | `NULL` | |
| 66 | INMEMORY_SERVICE_NAME | inmemory_service_name | text | `NULL` | |
| 67 | MEMOPTIMIZE_READ | memoptimize_read | text | 常量 'N' | |
| 68 | MEMOPTIMIZE_WRITE | memoptimize_write | text | 常量 'N' | |
| 69 | HAS_SENSITIVE_COLUMN | has_sensitive_column | text | 常量 'N' | |
| 70 | LOGICAL_REPLICATION | logical_replication | text | 常量 'N' | |

#### 回归测试
- 计划：`src/test/regress/ora_schedule`（仅 `oracle_compat_views`）
- SQL：`src/test/regress/sql/oracle_compat_views.sql`
- 预期：`src/test/regress/expected/oracle_compat_views.out`
- 覆盖点：
  - 超级用户：两张测试表出现在 `dba_all_tables`
  - 超级用户：`all_all_tables` 包含系统 schema（以 `pg_catalog`/`information_schema` 判定）
  - 普通用户：`user_all_tables` 仅包含自有表
  - 普通用户：`all_all_tables` 也包含系统 schema
  - 普通用户：对 `dba_all_tables` 无 SELECT 权限（`has_table_privilege = false`）

#### 运行方式
```bash
cd /home/dn/github/postgres/src/test/regress
./pg_regress --schedule ora_schedule
```

#### 变更与扩展
- 若需严格区分/过滤更多系统 schema（如进一步处理 `pg_toast`），可在 `dba_all_tables_base` 的系统过滤处扩展，同时补充回归断言。
- 若需新增 Oracle 兼容视图，可复用此基础函数模式（参数控制可见范围）。


