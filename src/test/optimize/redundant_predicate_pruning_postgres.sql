-- PostgreSQL Redundant Predicate Pruning Tests
-- 目标：验证优化器是否能识别并裁剪被更强条件蕴含的冗余谓词

DROP TABLE IF EXISTS t CASCADE;
CREATE TABLE t(id int primary key, a int, b int, c date);
INSERT INTO t
SELECT g, g%10, g%5, DATE 2023-01-01 + (g % 400)
FROM generate_series(1, 50000) g;

CREATE INDEX t_a_idx ON t(a);
CREATE INDEX t_c_idx ON t(c);
ANALYZE t;

\echo === 1) 不等式蕴含：a > 10 AND a > 5 （第二个可裁剪） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t WHERE a > 10 AND a > 5;

\echo === 2) 范围蕴含：c >= 2023-03-01 AND c >= 2023-01-01 （第二个可裁剪） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t WHERE c >= DATE 2023-03-01 AND c >= DATE 2023-01-01;

\echo === 3) IN-子集蕴含：a IN (3,4) AND a IN (1,2,3,4) （第二个可裁剪） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t WHERE a IN (3,4) AND a IN (1,2,3,4);

\echo === 4) 连接中子查询包含：
-- 子查询 S2 的结果包含 S1 时，WHERE a IN (S1) AND a IN (S2) 可裁剪一个 ===
DROP TABLE IF EXISTS d1; DROP TABLE IF EXISTS d2;
CREATE TABLE d1(x int primary key);
CREATE TABLE d2(x int primary key);
INSERT INTO d1 SELECT generate_series(1,1000);
INSERT INTO d2 SELECT generate_series(1,2000);
ANALYZE d1; ANALYZE d2;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t
WHERE a IN (SELECT x FROM d1)
  AND a IN (SELECT x FROM d2);

\echo === 5) EXISTS 蕴含：EXISTS(S) AND EXISTS(S with stronger predicate) （弱者可裁剪） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM t tt
WHERE EXISTS (SELECT 1 FROM d2 WHERE x = tt.a)
  AND EXISTS (SELECT 1 FROM d2 WHERE x = tt.a AND x > 0);

\echo === 6) OR 展开对比： (a=1 OR a=2) 与 a IN (1,2)（计划等价） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t WHERE a IN (1,2);
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM t WHERE a=1 OR a=2;

-- 清理
DROP TABLE d1; DROP TABLE d2; DROP TABLE t;
\echo === PostgreSQL redundant predicate pruning tests done ===
