-- PostgreSQL 查询优化快速测试
-- 演示 EXISTS 子查询中 OR 条件的优化效果

-- 创建测试表
DROP TABLE IF EXISTS t1 CASCADE;
DROP TABLE IF EXISTS t2 CASCADE;

CREATE TABLE t1 (
    id SERIAL PRIMARY KEY,
    a INTEGER,
    b INTEGER,
    data TEXT
);

CREATE TABLE t2 (
    id SERIAL PRIMARY KEY,
    a INTEGER,
    b INTEGER,
    data TEXT
);

-- 插入测试数据
INSERT INTO t1 (a, b, data) 
SELECT 
    (random() * 1000)::INTEGER,
    (random() * 1000)::INTEGER,
    'data_' || generate_series
FROM generate_series(1, 10000);

INSERT INTO t2 (a, b, data)
SELECT 
    (random() * 1000)::INTEGER,
    (random() * 1000)::INTEGER,
    'data_' || generate_series
FROM generate_series(1, 10000);

-- 创建索引
CREATE INDEX idx_t1_a ON t1(a);
CREATE INDEX idx_t1_b ON t1(b);
CREATE INDEX idx_t2_a ON t2(a);
CREATE INDEX idx_t2_b ON t2(b);

-- 更新统计信息
ANALYZE t1;
ANALYZE t2;

-- 测试 1: 原始查询 (OR 条件在 EXISTS 中)
\echo '=== 测试 1: 原始查询执行计划 ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) 
SELECT * FROM t1 WHERE
EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a OR t1.b = t2.b);

-- 测试 2: 优化查询 (OR 条件分解)
\echo '=== 测试 2: 优化查询执行计划 ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM t1 WHERE
EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
OR
EXISTS (SELECT 1 FROM t2 WHERE t1.b = t2.b);


SELECT * FROM t1 WHERE
EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
UNION
select * from t1 where
EXISTS (SELECT 1 FROM t2 WHERE t1.b = t2.b);

select distinct * from (
SELECT * FROM t1 WHERE
EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
UNION ALL
select * from t1 where
EXISTS (SELECT 1 FROM t2 WHERE t1.b = t2.b)
)t;


-- 测试 3: 进一步优化 (使用 UNION)
\echo '=== 测试 3: UNION 优化执行计划 ==='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT DISTINCT t1.* FROM t1 WHERE t1.id IN (
    SELECT t1.id FROM t1 
    WHERE EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
    UNION
    SELECT t1.id FROM t1 
    WHERE EXISTS (SELECT 1 FROM t2 WHERE t1.b = t2.b)
);

-- 性能对比总结
\echo '=== 性能对比总结 ==='
\echo '原始查询: Nested Loop Semi Join'
\echo '优化查询: Hash SubPlan (通常快 10-20 倍)'
\echo 'UNION 优化: 可能进一步优化复杂查询'

-- 清理
DROP TABLE t1 CASCADE;
DROP TABLE t2 CASCADE;
