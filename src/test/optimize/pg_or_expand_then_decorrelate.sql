-- PostgreSQL: OR-Expansion -> EXISTS -> 子查询提升（decorrelation）演示

-- 一、准备数据
DROP TABLE IF EXISTS t1 CASCADE;
DROP TABLE IF EXISTS t2 CASCADE;
DROP TABLE IF EXISTS t3 CASCADE;

CREATE TABLE t1 (
    id bigserial PRIMARY KEY,
    a  int,
    b  int,
    payload text
);

CREATE TABLE t2 (
    id bigserial PRIMARY KEY,
    a  int
);

CREATE TABLE t3 (
    id bigserial PRIMARY KEY,
    b  int
);

-- 数据量可按需调整以更清晰观察计划差异
INSERT INTO t1(a,b,payload)
SELECT (random()*2000)::int, (random()*2000)::int, 'p'||g
FROM generate_series(1, 200000) AS g;

INSERT INTO t2(a)
SELECT (random()*2000)::int FROM generate_series(1, 200000);

INSERT INTO t3(b)
SELECT (random()*2000)::int FROM generate_series(1, 200000);

CREATE INDEX idx_t1_a ON t1(a);
CREATE INDEX idx_t1_b ON t1(b);
CREATE INDEX idx_t2_a ON t2(a);
CREATE INDEX idx_t3_b ON t3(b);

ANALYZE t1; ANALYZE t2; ANALYZE t3;

-- 二、原始查询（含 OR, 单个 EXISTS 内部含 OR）
\echo '=== 原始：单 EXISTS 内含 OR ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM t1
WHERE EXISTS (
  SELECT 1 FROM t2 WHERE t1.a = t2.a
  UNION ALL
  SELECT 1 FROM t3 WHERE t1.b = t3.b
);

-- 为了与 OR-Expansion 对齐，这里用 UNION ALL 两个来源来模拟 OR，于计划层面类似 BitmapOr/Bitmap Index Scan 合并。

-- 三、OR 展开后得到两个 EXISTS（逻辑等价）
\echo '=== OR 展开：两个 EXISTS ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM t1
WHERE EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
   OR EXISTS (SELECT 1 FROM t3 WHERE t1.b = t3.b);

-- 四、对子查询进一步做“提升”：
--    将两个 EXISTS 分别改写为 LEFT JOIN 到预聚合结果（COUNT(*)），
--    然后在 WHERE 里判定计数是否为非空/非零。
\echo '=== 子查询提升：GROUP BY + LEFT JOIN + count 判定 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT t1.*
FROM t1
LEFT JOIN (
  SELECT a, COUNT(*) AS c1
  FROM t2
  GROUP BY a
) tt2 ON t1.a = tt2.a
LEFT JOIN (
  SELECT b, COUNT(*) AS c2
  FROM t3
  GROUP BY b
) tt3 ON t1.b = tt3.b
WHERE tt2.c1 IS NOT NULL OR tt3.c2 IS NOT NULL;

-- 可选：为了更易观察 Hash Join，可暂时禁用嵌套循环
-- SET enable_nestloop = off;

\echo '=== 完成：请对比三段计划的 Join/聚合形态与耗时 ==='


