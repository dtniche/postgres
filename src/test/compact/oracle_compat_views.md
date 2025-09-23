### Oracle 兼容视图设计（oracle_compat_views.sql）

#### 设计目标
- 提供与 Oracle DBA_ALL_TABLES / ALL_TABLES / USER_TABLES 等价的只读视图接口。
- 字段集合、名称与含义尽可能模拟 Oracle；数值型统一 NUMERIC，时间使用 TIMESTAMP（无时区），其他采用 TEXT。
- 可见性与权限模型贴近 Oracle：普通用户可用 ALL/USER 视图，不可用 DBA 视图。

#### 视图与权限
- dba_all_tables
  - 含义：所有表（含系统对象），DBA 视图
  - 实现：`SELECT * FROM all_tables_base(true, false, false)`
  - 权限：不授予 PUBLIC（`REVOKE ALL ON dba_all_tables FROM PUBLIC`）

- all_all_tables
  - 含义：当前用户可见的所有表，包含系统对象（模拟 Oracle ALL_TABLES）
  - 实现：`SELECT * FROM all_tables_base(true, false, true)`
  - 权限：`GRANT SELECT ON all_all_tables TO PUBLIC`

- user_all_tables
  - 含义：当前用户拥有的表
  - 实现：`SELECT * FROM all_tables_base(false, true, false)`
  - 权限：`GRANT SELECT ON user_all_tables TO PUBLIC`

#### 权限逻辑实现（与当前 `oracle_compat_views.sql` 保持一致）
- 基础函数入参约定（以 tables 类为例，其他 base 函数相同）：
  - `include_system_*`: 是否包含系统对象
  - `current_user_only`: 是否仅当前用户对象
  - `visible_only`: 是否仅限“当前可见对象”（避免 DBA 全量）
- DBA 模式判定：当且仅当 `NOT current_user_only AND NOT visible_only` 为真时，即视为请求 DBA 级别数据。
- 内部权限检查：在各 base 函数体内执行
  - `IF NOT current_user_only AND NOT visible_only THEN
       IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
         RAISE EXCEPTION 'permission denied for function ...: DBA-level access requires superuser privileges';
       END IF;
     END IF;`
  - 即：仅当请求 DBA 模式时才进行“当前有效用户是否超级用户”的检查；否则允许执行。
- 视图包装的参数策略：
  - `dba_*`/`dba_all_*` 视图：使用 DBA 模式（`current_user_only=false AND visible_only=false`），因此普通用户直接查询会因内部检查报错（同时也未对 PUBLIC 授权）。
  - `all_*`/`all_all_*` 视图：使用 `visible_only=true`，避免触发 DBA 模式检查，且对 PUBLIC 授权可读。
  - `user_*`/`user_all_*` 视图：使用 `current_user_only=true`，也不会触发 DBA 模式检查，且对 PUBLIC 授权可读。
- 特例：`col_privs_base` 使用 `SECURITY DEFINER`
  - 函数以定义者权限执行，`current_user` 在 SECURITY DEFINER 下等同于函数所有者的有效角色；因此即便以普通用户调用 DBA 模式，也不会触发“非超级用户”拒绝（现实现为可用）。
  - 设计含义：列权限信息函数以高权限收集数据，但最终通过上层视图的入参策略控制可见范围。
  - 回归测试据此验证：普通用户 DBA 模式调用 `tables_base/all_tables_base/arguments_base` 被拒绝；调用 `col_privs_base` 可成功返回（示例用 `SELECT 1 ... LIMIT 1`）。

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
  - 普通用户（通过 `SET ROLE regress_nosuper` 模拟）直接调用 base 函数的 DBA 模式：
    - `tables_base(true, false, false)` → 报错 `permission denied for function tables_base...`
    - `all_tables_base(true, false, false)` → 报错 `permission denied for function all_tables_base...`
    - `arguments_base(true, false, false)` → 报错 `permission denied for function arguments_base...`
    - `col_privs_base(true, false, false)` → SECURITY DEFINER 行为下可成功返回一行（回归用 `SELECT 1 ... LIMIT 1` 验证）

#### 运行方式
```bash
cd /home/dn/github/postgres/src/test/regress
./pg_regress --schedule ora_schedule
```

#### 新增：Arguments 视图设计

##### 视图与权限
- dba_arguments
  - 含义：所有函数参数（含系统函数），DBA 视图
  - 实现：`SELECT * FROM arguments_base(true, false, false)`
  - 权限：不授予 PUBLIC（`REVOKE ALL ON dba_arguments FROM PUBLIC`）

- all_arguments
  - 含义：当前用户可见的所有函数参数，包含系统函数
  - 实现：`SELECT * FROM arguments_base(true, false, true)`
  - 权限：`GRANT SELECT ON all_arguments TO PUBLIC`

- user_arguments
  - 含义：当前用户拥有的函数参数
  - 实现：`SELECT * FROM arguments_base(false, true, false)`
  - 权限：`GRANT SELECT ON user_arguments TO PUBLIC`

##### 数据来源与过滤
- 主来源：
  - `pg_proc p`（函数/过程：`prokind in ('f','p','a','w')`）
  - `pg_namespace n`（schema）
  - `pg_type t`（参数类型）
- 过滤：
  - 排除其他临时 schema：`NOT pg_is_other_temp_schema(n.oid)`
  - 是否包含系统函数：
    - 包含：不过滤系统 schema
    - 排除：排除 `pg_catalog`, `information_schema`, `pg_toast`
  - 仅当前用户：`pg_get_userbyid(p.proowner) = current_user`

##### 列映射表（29 列）
以下表格列出 Oracle DBA_ARGUMENTS 的列映射，PostgreSQL 实现完全匹配 Oracle 的29列结构。

| 序 | Oracle 含义 | 列名 | 类型 | 来源/规则 | 说明 |
|----|-------------|------|------|-----------|------|
| 1 | 所有者 | owner | text | `pg_get_userbyid(p.proowner)` | 函数 owner 名称 |
| 2 | 对象名 | object_name | text | `p.proname` | 函数名 |
| 3 | 包名 | package_name | text | `NULL` | PostgreSQL 无包概念 |
| 4 | 对象ID | object_id | numeric | `p.oid` | 函数 OID |
| 5 | 重载号 | overload | text | `'1'` | 字符串类型，简化处理 |
| 6 | 子程序ID | subprogram_id | numeric | `NULL` | PostgreSQL 无子程序概念 |
| 7 | 参数名 | argument_name | text | `p.proargnames[i]` | 参数名称 |
| 8 | 位置 | position | numeric | `i` | 参数位置（0=返回值） |
| 9 | 序列 | sequence | numeric | `i` | 与位置相同 |
| 10 | 数据级别 | data_level | numeric | `0` | 简化处理 |
| 11 | 数据类型 | data_type | text | `t.typname` | 参数类型名 |
| 12 | 默认标记 | defaulted | text | `NULL` | 简化处理 |
| 13 | 默认值 | default_value | text | `NULL` | 简化处理 |
| 14 | 默认长度 | default_length | numeric | `NULL` | 简化处理 |
| 15 | 输入输出 | in_out | text | `proargmodes[i]` 映射 | IN/OUT/IN OUT |
| 16 | 数据长度 | data_length | numeric | `t.typlen` | 类型长度 |
| 17 | 精度 | data_precision | numeric | `t.typtypmod` | 数值类型精度 |
| 18 | 标度 | data_scale | numeric | `t.typtypmod & 65535` | 数值类型标度 |
| 19 | 基数 | radix | numeric | `10` | 数值类型基数 |
| 20 | 字符集 | character_set_name | text | `NULL` | 简化处理 |
| 21 | 类型所有者 | type_owner | text | `nt.nspname` | 类型所属 schema |
| 22 | 类型名 | type_name | text | `t.typname` | 类型名称 |
| 23 | 子类型名 | type_subname | text | `NULL` | 简化处理 |
| 24 | 类型链接 | type_link | text | `NULL` | 简化处理 |
| 25 | 类型对象类型 | type_object_type | text | `NULL` | 简化处理 |
| 26 | PL/SQL类型 | pls_type | text | `t.typname` | 与类型名相同 |
| 27 | 字符长度 | char_length | numeric | `t.typtypmod` | 字符串类型长度 |
| 28 | 字符使用 | char_used | text | `B/C` | 字节/字符长度标志 |
| 29 | 源容器ID | origin_con_id | numeric | `NULL` | 简化处理 |

##### 实现特点
- 使用 PL/pgSQL 函数实现，支持复杂的参数展开逻辑
- 返回值作为 position=0 的特殊参数处理
- 支持 IN/OUT/IN OUT 参数方向映射
- 数值类型精度和标度正确解析
- 字符串类型长度信息完整保留

#### 新增：列权限视图设计 (COL_PRIVS)

##### 1. 视图概述
- **DBA_COL_PRIVS**: 所有列权限信息（含系统对象），DBA视图
- **ALL_COL_PRIVS**: 当前用户可见的所有列权限，包含系统对象
- **USER_COL_PRIVS**: 当前用户拥有的列权限（不含owner列）

##### 2. 实现方式
- **基础函数**: `col_privs_base(include_system_objects, current_user_only, visible_only)`
- **参数控制**: 通过三个布尔参数控制数据范围和权限
- **数据源**: `pg_class` + `pg_attribute` + `pg_namespace` 系统表
- **权限控制**: 通过基础函数的内部逻辑实现DBA级别访问控制
- **类型安全**: 所有返回值显式转换为 `text` 类型，确保类型一致性

##### 3. 权限模型
- **DBA_COL_PRIVS**: `col_privs_base(true, false, false)` - 需要超级用户权限
- **ALL_COL_PRIVS**: `col_privs_base(true, false, true)` - 公开访问
- **USER_COL_PRIVS**: `col_privs_base(false, true, false)` - 当前用户数据

##### 4. 数据来源
- `pg_class`: 表定义信息
- `pg_attribute`: 列定义信息
- `pg_namespace`: 模式信息
- 支持系统表和用户表

##### 5. 过滤规则
- 系统对象过滤：根据 `nspname` 判断
- 用户对象过滤：根据 `relowner` 判断
- 支持表、分区表

##### 6. 列映射表（9列）

**DBA_COL_PRIVS 和 USER_COL_PRIVS 视图结构：**
| 序 | Oracle 含义 | 列名 | 类型 | 来源/规则 | 说明 |
|----|-------------|------|------|-----------|------|
| 1 | 被授权者 | grantee | text | `'PUBLIC'` | 模拟权限信息 |
| 2 | 所有者 | owner | text | `pg_get_userbyid(c.relowner)` | 表所有者 |
| 3 | 表名 | table_name | text | `c.relname` | 表名 |
| 4 | 列名 | column_name | text | `a.attname` | 列名 |
| 5 | 授权者 | grantor | text | `pg_get_userbyid(c.relowner)` | 表所有者 |
| 6 | 权限 | privilege | text | `'SELECT'` | 模拟权限 |
| 7 | 可授权 | grantable | text | `'NO'` | 模拟权限 |
| 8 | 公共 | common | text | `'NO'` | 模拟权限 |
| 9 | 继承 | inherited | text | `'NO'` | 模拟权限 |

**ALL_COL_PRIVS 视图结构（与Oracle完全匹配）：**
| 序 | Oracle 含义 | 列名 | 类型 | 来源/规则 | 说明 |
|----|-------------|------|------|-----------|------|
| 1 | 授权者 | grantor | text | `pg_get_userbyid(c.relowner)` | 表所有者 |
| 2 | 被授权者 | grantee | text | `'PUBLIC'` | 模拟权限信息 |
| 3 | 表模式 | table_schema | name | `n.nspname` | 模式名 |
| 4 | 表名 | table_name | text | `c.relname` | 表名 |
| 5 | 列名 | column_name | text | `a.attname` | 列名 |
| 6 | 权限 | privilege | text | `'SELECT'` | 模拟权限 |
| 7 | 可授权 | grantable | text | `'NO'` | 模拟权限 |
| 8 | 公共 | common | text | `'NO'` | 模拟权限 |
| 9 | 继承 | inherited | text | `'NO'` | 模拟权限 |

##### 7. 特殊说明
- PostgreSQL的列权限管理相对简单，这里主要展示表结构
- 实际权限信息需要从pg_class_acl等系统表获取
- 当前实现为模拟权限信息，用于兼容性测试
- **ALL_COL_PRIVS** 视图包含 `table_schema` 列，与Oracle结构完全匹配
- **DBA_COL_PRIVS** 和 **USER_COL_PRIVS** 视图不包含 `table_schema` 列
- 所有视图都通过 `col_privs_base` 基础函数实现，确保数据一致性

#### 新增：列注释视图设计 (COL_COMMENTS)

##### 1. 视图概述
- **DBA_COL_COMMENTS**: 所有列注释（含系统对象），DBA视图
- **ALL_COL_COMMENTS**: 所有列注释（含系统对象），ALL视图  
- **USER_COL_COMMENTS**: 当前用户拥有的列注释，USER视图

##### 2. 实现方式
- **基础函数**: `col_comments_base(include_system_objects, current_user_only, visible_only)`
- **参数控制**: 通过三个布尔参数控制数据范围和权限
- **数据源**: `pg_description` 系统表 + `pg_class` + `pg_attribute`

##### 3. 权限模型
- **DBA_COL_COMMENTS**: `col_comments_base(true, false, false)` - 需要超级用户权限
- **ALL_COL_COMMENTS**: `col_comments_base(true, false, true)` - 公开访问
- **USER_COL_COMMENTS**: `col_comments_base(false, true, false)` - 当前用户数据

##### 4. 数据来源
- **主要表**: `pg_description` (存储注释信息)
- **关联表**: `pg_class` (表信息) + `pg_attribute` (列信息)
- **过滤条件**: 基于 `objoid` 和 `classoid` 关联

##### 5. 过滤规则
- **系统对象**: `include_system_objects` 参数控制是否包含系统表
- **用户限制**: `current_user_only` 参数限制为当前用户拥有的对象
- **可见性**: `visible_only` 参数控制基于权限的可见性过滤

##### 6. 列映射表（5列）
| 序号 | 列名 | 数据类型 | Oracle对应 | PostgreSQL来源 | 说明 |
|------|------|----------|------------|----------------|------|
| 1 | owner | text | OWNER | pg_get_userbyid(c.relowner) | 表所有者 |
| 2 | table_name | text | TABLE_NAME | c.relname | 表名 |
| 3 | column_name | text | COLUMN_NAME | a.attname | 列名 |
| 4 | comments | text | COMMENTS | d.description | 列注释 |
| 5 | origin_con_id | numeric | ORIGIN_CON_ID | NULL | Oracle容器ID（PostgreSQL中为NULL） |

##### 7. 实现特点
- **注释获取**: 从 `pg_description` 表获取列注释，`objoid` 对应 `pg_attribute.attrelid`，`objsubid` 对应 `pg_attribute.attnum`
- **权限控制**: 通过基础函数的内部逻辑实现DBA级别访问控制
- **类型安全**: 所有返回值显式转换为 `text` 类型，确保类型一致性
- **兼容性**: 完全匹配Oracle DBA_COL_COMMENTS视图结构

##### 8. 特殊说明
- PostgreSQL的列注释存储在 `pg_description` 系统表中
- 通过 `objoid` 和 `objsubid` 字段关联到具体的列
- 当前实现支持所有用户表的列注释查询
- 注释内容直接来自数据库，确保数据真实性

#### 新增视图的方法和步骤

##### 1. 设计阶段
1. **分析Oracle视图结构**
   - 查询Oracle数据字典获取目标视图的完整列信息
   - 记录列名、数据类型、约束条件、列顺序
   - 确定权限模型（DBA/ALL/USER）

2. **Oracle字段内容分析工具**
   - **工具文件**: `oracle_field_analysis.py`
   - **用途**: 深入分析Oracle实际数据，获取字段值分布、样本数据和NULL值统计
   - **功能模块**:
     ```python
     # 连接Oracle数据库（SYSDBA模式）
     def connect_oracle()
     
     # 获取关键字段的值分布
     def get_oracle_field_values(connection)
     # 查询字段如：status, logging, backed_up, temporary, buffer_pool等
     
     # 获取样本数据（前10行）
     def get_sample_data(connection)
     
     # 获取NULL值统计
     def get_null_value_stats(connection)
     ```
   - **输出文件**: `oracle_field_analysis.json` 包含：
     - `field_values`: 各字段的实际值分布（如status: ['VALID', 'INVALID']）
     - `sample_data`: 样本数据示例（前10行记录）
     - `null_stats`: NULL值统计信息（各字段的非NULL值数量）
   - **使用场景**:
     - 验证字段值的合理性（如status字段只有'VALID'/'INVALID'）
     - 确定默认值和特殊值的处理逻辑
     - 分析字段的NULL值比例，指导PostgreSQL实现
     - 为列映射提供实际数据参考
   - **运行示例**:
     ```bash
     python3 oracle_field_analysis.py
     # 输出: oracle_field_analysis.json
     ```

3. **设计PostgreSQL映射**
   - 确定数据来源（pg_class, pg_proc, pg_namespace等）
   - 设计过滤逻辑（系统对象、用户权限）
   - 规划列映射和数据类型转换
   - 参考Oracle字段分析结果确定默认值

##### 2. 实现阶段
1. **运行Oracle字段分析**
   ```bash
   # 在实现前先分析Oracle实际数据
   python3 oracle_field_analysis.py
   
   # 查看分析结果
   cat oracle_field_analysis.json | jq '.field_values'
   cat oracle_field_analysis.json | jq '.sample_data[0]'
   cat oracle_field_analysis.json | jq '.null_stats'
   ```

2. **创建基础函数**
   ```sql
   CREATE OR REPLACE FUNCTION view_base(
       include_system_objects boolean DEFAULT true,
       current_user_only boolean DEFAULT false
   )
   RETURNS TABLE (
       -- 按Oracle列顺序定义返回表结构
       -- 参考oracle_field_analysis.json确定默认值
       column1 text,
       column2 numeric,
       ...
   )
   LANGUAGE plpgsql
   STABLE
   AS $$
   -- 实现逻辑
   -- 使用Oracle字段分析结果确定默认值
   $$;
   ```

2. **创建三个视图**
   ```sql
   -- DBA视图（包含系统对象，所有用户）
   CREATE VIEW dba_view AS 
   SELECT * FROM view_base(true, false);
   
   -- ALL视图（包含系统对象，所有用户）
   CREATE VIEW all_view AS 
   SELECT * FROM view_base(true, false);
   
   -- USER视图（仅当前用户对象）
   CREATE VIEW user_view AS 
   SELECT * FROM view_base(false, true);
   ```

3. **设置权限**
   ```sql
   -- DBA视图：不授予PUBLIC
   REVOKE ALL ON dba_view FROM PUBLIC;
   
   -- ALL/USER视图：授予PUBLIC
   GRANT SELECT ON all_view TO PUBLIC;
   GRANT SELECT ON user_view TO PUBLIC;
   ```

##### 3. 测试阶段
1. **验证Oracle字段分析结果**
   ```bash
   # 重新运行Oracle字段分析，确保数据是最新的
   python3 oracle_field_analysis.py
   
   # 检查关键字段的值分布是否合理
   cat oracle_field_analysis.json | jq '.field_values.status'
   cat oracle_field_analysis.json | jq '.field_values.logging'
   ```

2. **更新验证配置**
   - 验证配置脚本目录:`src/test/compact`下
   - 在 `validation_config.yaml` 中添加新视图到验证列表
   - 已添加的视图：`dba_col_comments`, `all_col_comments`, `user_col_comments`
   - 运行兼容性验证：`python3 oracle_compat_validation.py --views`

3. **兼容性验证流程**
   ```bash
   # 验证特定视图的兼容性
   python3 oracle_compat_validation.py --views dba_col_comments all_col_comments user_col_comments
   
   # 验证单个视图（如user_col_comments）
   python3 oracle_compat_validation.py --views user_col_comments
   
   # 生成详细报告
   python3 oracle_compat_validation.py --views dba_col_comments --output detailed_report.txt --json results.json
   ```

4. **根据验证结果修正实现**
   - 查看 `validation_results.json` 中的Oracle列结构
   - 对比PostgreSQL和Oracle的列顺序、数据类型
   - 修正PostgreSQL实现以匹配Oracle结构
   - 重新运行验证直到兼容性评分达到100%

   **修正步骤详解**：
   ```bash
   # 1. 查看Oracle列结构
   python3 -c "
   import json
   with open('validation_results.json', 'r') as f:
       data = json.load(f)
   for result in data['results']:
       if result['view_name'] == 'user_col_comments':
           print('Oracle列结构:')
           for col in result['oracle']['columns']:
               print(f'{col[\"ordinal_position\"]:2d}. {col[\"name\"]:<30} {col[\"data_type\"]:<15}')
           break
   "
   
   # 2. 对比PostgreSQL列结构
   psql -d postgres -c "SELECT column_name, ordinal_position, data_type FROM information_schema.columns WHERE table_name = 'user_col_comments' ORDER BY ordinal_position;"
   
   # 3. 修正PostgreSQL实现
   # - 调整RETURNS TABLE中的列顺序
   # - 修正数据类型映射
   # - 确保列名完全匹配
   
   # 4. 重新创建视图
   psql -d postgres -f src/backend/catalog/oracle_compat_views.sql
   
   # 5. 重新验证
   python3 oracle_compat_validation.py --views user_col_comments
   ```

5. **验证结果分析**
   ```bash
   # 查看验证结果
   cat validation_results.json | jq '.results[] | select(.view_name == "user_col_comments")'
   
   # 查看详细报告
   cat validation_report.txt
   ```

6. **更新回归测试**
   - 在 `src/test/regress/sql/oracle_compat_views.sql` 中添加测试用例
   - 测试列数量、列名、数据类型
   - 测试权限模型（普通用户无法访问DBA视图）
   - 参考Oracle字段分析结果编写数据验证测试

7. **运行回归测试**
   ```bash
   cd src/test/regress
   ./pg_regress --schedule ora_schedule
   ```


8. **测试流程检查清单**
   - [x] 新视图已添加到 `validation_config.yaml` (dba_col_comments, all_col_comments, user_col_comments)
   - [x] 运行 `python3 oracle_compat_validation.py --views dba_col_comments` 验证元数据
   - [x] 检查列数量是否匹配Oracle (5列)
   - [x] 检查列顺序是否与Oracle一致
   - [x] 检查数据类型映射是否正确
   - [x] 检查列名是否完全匹配（大小写不敏感）
   - [x] 兼容性评分达到100%
   - [x] 运行回归测试通过
   - [x] 更新设计文档和README

9. **快速验证工具**
   ```bash
   # 使用自动化验证脚本
   ./validate_new_view.sh user_col_comments
   
   # 查看详细测试流程示例
   cat test_workflow_example.md
   ```

10. **Oracle字段分析工具**
   ```bash
   # 运行Oracle字段内容分析
   python3 oracle_field_analysis.py
   
   # 查看字段值分布
   cat oracle_field_analysis.json | jq '.field_values'
   
   # 查看样本数据
   cat oracle_field_analysis.json | jq '.sample_data[0]'
   
   # 查看NULL值统计
   cat oracle_field_analysis.json | jq '.null_stats'
   ```

##### 4. 文档更新
1. **更新设计文档**
   - 在 `oracle_compat_views.md` 中添加新视图设计说明
   - 包含列映射表、数据来源、过滤规则
   - 记录实现特点和注意事项

2. **更新README**
   - 在 `README.md` 中更新验证视图列表
   - 更新列数统计信息

##### 5. 最佳实践
1. **列顺序严格匹配Oracle**
   - 使用 `RETURNS TABLE` 按Oracle顺序定义列
   - 确保列位置与Oracle完全一致

2. **数据类型映射**
   - 数值类型：`numeric` → `NUMBER`
   - 文本类型：`text` → `VARCHAR2/CHAR/CLOB/LONG`
   - 时间类型：`timestamp` → `DATE/TIMESTAMP`
   - 标识符：`name` → `VARCHAR2`

3. **权限模型一致性**
   - DBA视图：仅超级用户可访问
   - ALL视图：所有用户可访问，包含系统对象
   - USER视图：所有用户可访问，仅当前用户对象

4. **错误处理**
   - 使用 `COALESCE` 处理NULL值
   - 提供合理的默认值
   - 确保函数稳定性（STABLE）

##### 6. 示例：新增DBA_INDEXES视图
```sql
-- 1. 创建基础函数
CREATE OR REPLACE FUNCTION indexes_base(
    include_system_objects boolean DEFAULT true,
    current_user_only boolean DEFAULT false
)
RETURNS TABLE (
    owner text,
    index_name text,
    table_name text,
    table_owner text,
    table_type text,
    uniqueness text,
    -- ... 其他列
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    FOR rec IN
        SELECT i.oid, i.relname, c.relname as table_name, 
               pg_get_userbyid(i.relowner) as owner_name
        FROM pg_class i
        JOIN pg_index ix ON ix.indexrelid = i.oid
        JOIN pg_class c ON c.oid = ix.indrelid
        WHERE i.relkind = 'i'
          AND (include_system_objects OR c.relnamespace NOT IN (11, 99, 99))
          AND (NOT current_user_only OR pg_get_userbyid(i.relowner) = current_user)
    LOOP
        owner := rec.owner_name;
        index_name := rec.relname;
        table_name := rec.table_name;
        -- ... 设置其他列
        RETURN NEXT;
    END LOOP;
END;
$$;

-- 2. 创建视图
CREATE VIEW dba_indexes AS SELECT * FROM indexes_base(true, false);
CREATE VIEW all_indexes AS SELECT * FROM indexes_base(true, false);
CREATE VIEW user_indexes AS SELECT * FROM indexes_base(false, true);

-- 3. 设置权限
REVOKE ALL ON dba_indexes FROM PUBLIC;
GRANT SELECT ON all_indexes TO PUBLIC;
GRANT SELECT ON user_indexes TO PUBLIC;
```

#### Oracle字段分析工具使用指南

##### 工具概述
`oracle_field_analysis.py` 是设计阶段的重要工具，用于深入分析Oracle实际数据，为PostgreSQL实现提供准确的数据参考。

##### 主要功能
1. **字段值分布分析**: 获取关键字段的所有可能值
2. **样本数据提取**: 获取前10行实际数据示例  
3. **NULL值统计**: 分析各字段的NULL值比例
4. **数据质量验证**: 确保Oracle数据的合理性和一致性

##### 使用方法
```bash
# 1. 运行分析
python3 oracle_field_analysis.py

# 2. 查看字段值分布
cat oracle_field_analysis.json | jq '.field_values'

# 3. 查看样本数据
cat oracle_field_analysis.json | jq '.sample_data[0]'

# 4. 查看NULL值统计
cat oracle_field_analysis.json | jq '.null_stats'
```

##### 分析结果解读
- **field_values**: 各字段的实际值分布，用于确定默认值和枚举值
- **sample_data**: 样本数据，用于验证数据格式和内容
- **null_stats**: NULL值统计，用于确定哪些字段可以为NULL

##### 在开发流程中的应用
1. **设计阶段**: 分析Oracle字段内容，确定实现策略
2. **实现阶段**: 参考分析结果设置默认值和约束
3. **测试阶段**: 验证PostgreSQL实现与Oracle数据的一致性

##### 示例输出
```json
{
  "timestamp": "2025-09-22T13:45:00",
  "field_values": {
    "status": ["VALID", "INVALID"],
    "logging": ["YES", "NO"],
    "temporary": ["N", "Y"],
    "partitioned": ["NO", "YES"]
  },
  "sample_data": [
    {
      "owner": "SYS",
      "table_name": "TAB$",
      "status": "VALID",
      "logging": "YES",
      "temporary": "N"
    }
  ],
  "null_stats": {
    "total_tables": 1000,
    "tablespace_name_not_null": 950,
    "cluster_name_not_null": 0
  }
}
```

#### 变更与扩展
- 若需严格区分/过滤更多系统 schema（如进一步处理 `pg_toast`），可在基础函数的系统过滤处扩展，同时补充回归断言。
- 若需新增 Oracle 兼容视图，可复用此基础函数模式（参数控制可见范围）。
- Arguments 视图支持函数参数信息的完整查询，适用于 API 文档生成和代码分析。
- COL_COMMENTS 视图支持列注释信息的查询，适用于数据库文档生成和元数据管理。
- 新增视图时请严格按照上述步骤进行，确保与Oracle的完全兼容性。


