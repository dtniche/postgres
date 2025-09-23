-- Oracle兼容性视图回归测试
-- 测试所有6个Oracle兼容视图的基本功能、权限和内容
-- 首先创建Oracle兼容视图
\ i../../../ src / backend / catalog / oracle_compat_views.sql -- 创建测试表用于验证
CREATE TABLE test_table1 (id int, name text);
CREATE TABLE test_table2 (id int, value numeric);
-- 测试DBA_TABLES视图（超级用户视图）
SELECT COUNT(*)
FROM dba_tables;
SELECT COUNT(*)
FROM dba_tables
WHERE owner = 'postgres';
SELECT table_name,
    status,
    num_rows
FROM dba_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试ALL_TABLES视图（包含系统表）
SELECT COUNT(*)
FROM all_tables;
SELECT COUNT(*)
FROM all_tables
WHERE owner = 'postgres';
SELECT table_name,
    status,
    num_rows
FROM all_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试USER_TABLES视图（当前用户表，不含owner列）
SELECT COUNT(*)
FROM user_tables;
SELECT table_name,
    status,
    num_rows
FROM user_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试DBA_ALL_TABLES视图（别名）
SELECT COUNT(*)
FROM dba_all_tables;
SELECT table_name,
    status,
    num_rows
FROM dba_all_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试ALL_ALL_TABLES视图（别名）
SELECT COUNT(*)
FROM all_all_tables;
SELECT table_name,
    status,
    num_rows
FROM all_all_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试USER_ALL_TABLES视图（别名）
SELECT COUNT(*)
FROM user_all_tables;
SELECT table_name,
    status,
    num_rows
FROM user_all_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试列数匹配（根据设计文档应该是70/70/69列）
SELECT (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'dba_tables'
    ) as dba_tables_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'all_tables'
    ) as all_tables_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'user_tables'
    ) as user_tables_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'dba_all_tables'
    ) as dba_all_tables_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'all_all_tables'
    ) as all_all_tables_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'user_all_tables'
    ) as user_all_tables_cols;
-- 测试数据类型兼容性（NUMERIC类型映射）
SELECT column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'dba_tables'
    AND column_name IN (
        'pct_free',
        'num_rows',
        'blocks',
        'last_analyzed'
    )
ORDER BY ordinal_position;
-- 测试权限模型（超级用户应该能访问所有视图）
SELECT has_table_privilege('dba_tables', 'SELECT') as can_select_dba_tables,
    has_table_privilege('all_tables', 'SELECT') as can_select_all_tables,
    has_table_privilege('user_tables', 'SELECT') as can_select_user_tables,
    has_table_privilege('dba_all_tables', 'SELECT') as can_select_dba_all_tables,
    has_table_privilege('all_all_tables', 'SELECT') as can_select_all_all_tables,
    has_table_privilege('user_all_tables', 'SELECT') as can_select_user_all_tables;
-- 测试视图内容一致性（dba_tables和dba_all_tables应该相同）
SELECT (
        SELECT COUNT(*)
        FROM dba_tables
    ) = (
        SELECT COUNT(*)
        FROM dba_all_tables
    ) as dba_views_match,
    (
        SELECT COUNT(*)
        FROM all_tables
    ) = (
        SELECT COUNT(*)
        FROM all_all_tables
    ) as all_views_match,
    (
        SELECT COUNT(*)
        FROM user_tables
    ) = (
        SELECT COUNT(*)
        FROM user_all_tables
    ) as user_views_match;
-- 测试系统表包含情况（all_tables应该包含系统表）
SELECT COUNT(*) as system_tables_count
FROM all_tables
WHERE owner IN ('postgres')
    AND tablespace_name IN ('pg_catalog', 'information_schema');
-- 测试特定列的数据类型和值
SELECT table_name,
    status,
    partitioned,
    temporary,
    logging,
    compression,
    inmemory,
    external
FROM dba_tables
WHERE table_name LIKE 'test_%'
ORDER BY table_name;
-- 测试DBA_ARGUMENTS视图（超级用户视图）
SELECT COUNT(*)
FROM dba_arguments;
SELECT COUNT(*)
FROM dba_arguments
WHERE owner = 'postgres';
SELECT object_name,
    argument_name,
    data_type,
    in_out,
    position
FROM dba_arguments
WHERE object_name LIKE '%abs%'
ORDER BY object_name,
    position
LIMIT 10;
-- 测试ALL_ARGUMENTS视图（包含系统函数）
SELECT COUNT(*)
FROM all_arguments;
SELECT COUNT(*)
FROM all_arguments
WHERE owner = 'postgres';
SELECT object_name,
    argument_name,
    data_type,
    in_out,
    position
FROM all_arguments
WHERE object_name LIKE '%abs%'
ORDER BY object_name,
    position
LIMIT 10;
-- 测试USER_ARGUMENTS视图（当前用户函数，不含owner列）
SELECT COUNT(*)
FROM user_arguments;
SELECT object_name,
    argument_name,
    data_type,
    in_out,
    position
FROM user_arguments
WHERE object_name LIKE '%abs%'
ORDER BY object_name,
    position
LIMIT 10;
-- 测试列数匹配（根据Oracle DBA_ARGUMENTS应该是25列）
SELECT (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'dba_arguments'
    ) as dba_arguments_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'all_arguments'
    ) as all_arguments_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'user_arguments'
    ) as user_arguments_cols;
-- 测试数据类型兼容性（NUMERIC类型映射）
SELECT column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'dba_arguments'
    AND column_name IN (
        'object_id',
        'overload',
        'position',
        'sequence',
        'data_level',
        'data_length',
        'data_precision',
        'data_scale',
        'radix',
        'char_length'
    )
ORDER BY ordinal_position;
-- 测试权限模型（超级用户应该能访问所有视图）
SELECT has_table_privilege('dba_arguments', 'SELECT') as can_select_dba_arguments,
    has_table_privilege('all_arguments', 'SELECT') as can_select_all_arguments,
    has_table_privilege('user_arguments', 'SELECT') as can_select_user_arguments;
-- 测试视图内容一致性（dba_arguments和all_arguments应该相同）
SELECT (
        SELECT COUNT(*)
        FROM dba_arguments
    ) = (
        SELECT COUNT(*)
        FROM all_arguments
    ) as dba_all_arguments_match,
    (
        SELECT COUNT(*)
        FROM user_arguments
    ) <= (
        SELECT COUNT(*)
        FROM all_arguments
    ) as user_arguments_subset;
-- 测试系统函数包含情况（all_arguments应该包含系统函数）
SELECT COUNT(*) as system_functions_count
FROM all_arguments
WHERE owner IN ('postgres')
    AND type_owner IN ('pg_catalog', 'information_schema');
-- 测试特定列的数据类型和值
SELECT object_name,
    argument_name,
    data_type,
    in_out,
    position,
    data_length,
    data_precision,
    data_scale
FROM dba_arguments
WHERE object_name LIKE '%abs%'
    AND position <= 1
ORDER BY object_name,
    position
LIMIT 5;
-- 测试参数方向（IN/OUT/IN OUT）
SELECT in_out,
    COUNT(*) as count
FROM dba_arguments
GROUP BY in_out
ORDER BY in_out;
-- 测试返回值参数（position=0）
SELECT object_name,
    argument_name,
    data_type,
    in_out,
    position
FROM dba_arguments
WHERE position = 0
ORDER BY object_name
LIMIT 5;
-- ========================================
-- 测试列权限视图 (COL_PRIVS)
-- ========================================
-- 测试DBA_COL_PRIVS视图（超级用户视图）
SELECT COUNT(*)
FROM dba_col_privs;
SELECT COUNT(*)
FROM dba_col_privs
WHERE owner = 'postgres';
-- 测试ALL_COL_PRIVS视图（包含系统对象）
SELECT COUNT(*)
FROM all_col_privs;
SELECT COUNT(*)
FROM all_col_privs
WHERE table_schema = 'postgres';
SELECT grantor,
    grantee,
    table_schema,
    table_name,
    column_name,
    privilege
FROM all_col_privs
WHERE table_name LIKE '%pg_%'
ORDER BY table_name,
    column_name
LIMIT 10;
-- 测试USER_COL_PRIVS视图（当前用户列权限，不含owner列）
SELECT COUNT(*)
FROM user_col_privs;
SELECT grantee,
    owner,
    table_name,
    column_name,
    privilege
FROM user_col_privs
WHERE table_name LIKE '%pg_%'
ORDER BY table_name,
    column_name
LIMIT 10;
-- 测试列数匹配（根据Oracle DBA_COL_PRIVS应该是9列）
SELECT (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'dba_col_privs'
    ) as dba_col_privs_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'all_col_privs'
    ) as all_col_privs_cols,
    (
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_name = 'user_col_privs'
    ) as user_col_privs_cols;
-- 测试数据类型兼容性（TEXT类型映射）
SELECT column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'dba_col_privs'
    AND column_name IN (
        'grantee',
        'owner',
        'table_name',
        'column_name',
        'grantor',
        'privilege',
        'grantable',
        'common',
        'inherited'
    )
ORDER BY ordinal_position;
-- 测试权限模型（超级用户应该能访问所有视图）
SELECT has_table_privilege('dba_col_privs', 'SELECT') as can_select_dba_col_privs,
    has_table_privilege('all_col_privs', 'SELECT') as can_select_all_col_privs,
    has_table_privilege('user_col_privs', 'SELECT') as can_select_user_col_privs;
-- 测试视图内容一致性（dba_col_privs和all_col_privs应该相同）
SELECT (
        SELECT COUNT(*)
        FROM dba_col_privs
    ) = (
        SELECT COUNT(*)
        FROM all_col_privs
    ) as dba_all_col_privs_match,
    (
        SELECT COUNT(*)
        FROM user_col_privs
    ) <= (
        SELECT COUNT(*)
        FROM all_col_privs
    ) as user_col_privs_subset;
-- 测试系统对象包含情况（all_col_privs应该包含系统表列）
SELECT COUNT(*) as system_columns_count
FROM all_col_privs
WHERE table_schema = 'postgres'
    AND table_name LIKE 'pg_%';
-- 清理测试表
DROP TABLE test_table1,
test_table2;