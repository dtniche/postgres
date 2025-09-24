-- PostgreSQL: Correlated subquery decorrelation demo
-- 将相关标量子查询 + 聚合改写为 GROUP BY + JOIN，对比执行计划

-- 1. 准备数据
DROP TABLE IF EXISTS t1 CASCADE;
DROP TABLE IF EXISTS t2 CASCADE;

CREATE TABLE t1 (
    id  bigserial PRIMARY KEY,
    c   int,
    a   numeric
);

CREATE TABLE t2 (
    id  bigserial PRIMARY KEY,
    c   int,
    b   numeric
);

-- 数据量可按需调整
INSERT INTO t1 (c, a)
SELECT (random()*1000)::int, round((random()*100)::numeric, 2)
FROM generate_series(1, 100000);

INSERT INTO t2 (c, b)
SELECT (random()*1000)::int, round((random()*100)::numeric, 2)
FROM generate_series(1, 300000);

CREATE INDEX idx_t1_c ON t1(c);
CREATE INDEX idx_t2_c ON t2(c);

ANALYZE t1;
ANALYZE t2;

-- 2. 原始写法：相关标量子查询 + 聚合
\echo '=== 原始：相关子查询 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM t1
WHERE t1.a > 1.2 * (
  SELECT avg(t2.b)
  FROM t2
  WHERE t2.c = t1.c
);

-- 3. 改写写法：先聚合再 JOIN（常使优化器选 Hash Join）
\echo '=== 改写：GROUP BY + JOIN ==='
EXPLAIN (ANALYZE, BUFFERS)
WITH g AS (
  SELECT c, avg(b) AS avg_b
  FROM t2
  GROUP BY c
)
SELECT t1.*
FROM t1
JOIN g ON g.c = t1.c
WHERE t1.a > 1.2 * g.avg_b;

-- 可选：禁用嵌套循环以便更易观测 Hash Join
-- SET enable_nestloop = off;

\echo '=== 完成：请对比两段计划的 Join/聚合形态与耗时 ==='


