-- PostgreSQL: TPC-DS Q95 风格的 IN 子查询子集裁剪示例
-- 结构：
--   条件1：ws1.ws_order_number IN (SELECT ws_order_number FROM ws_wh)
--   条件2：ws1.ws_order_number IN (
--              SELECT wr_order_number FROM web_returns, ws_wh
--              WHERE wr_order_number = ws_wh.ws_order_number)
-- 其中条件2的结果集合是条件1的子集，故条件1可被裁剪。

\echo === Setup ===
DROP TABLE IF EXISTS web_returns CASCADE;
DROP TABLE IF EXISTS ws_wh CASCADE;
DROP TABLE IF EXISTS ws1 CASCADE;

CREATE TABLE ws_wh(
  ws_order_number int PRIMARY KEY
);

CREATE TABLE web_returns(
  wr_order_number int NOT NULL
);

CREATE TABLE ws1(
  ws_order_number int NOT NULL
);

-- 准备数据：ws_wh = 1..200000；web_returns = 偶数（子集）；ws1 = 随机采样
INSERT INTO ws_wh
SELECT g FROM generate_series(1,200000) g;

INSERT INTO web_returns
SELECT g FROM generate_series(2,200000,2) g;  -- 偶数子集

INSERT INTO ws1
SELECT (random()*200000)::int + 1 FROM generate_series(1,100000);

ANALYZE ws_wh; ANALYZE web_returns; ANALYZE ws1;

-- 索引
CREATE INDEX IF NOT EXISTS idx_ws1_order ON ws1(ws_order_number);
CREATE INDEX IF NOT EXISTS idx_wr_order ON web_returns(wr_order_number);

\echo === Query A: 同时包含“超集”与“子集”的 IN 条件 ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM ws1
WHERE ws_order_number IN (SELECT ws_order_number FROM ws_wh)
  AND ws_order_number IN (
        SELECT wr_order_number
        FROM web_returns, ws_wh
        WHERE wr_order_number = ws_wh.ws_order_number
      );

\echo === Query B: 仅保留“子集”条件（与 A 结果应等价） ===
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM ws1
WHERE ws_order_number IN (
        SELECT wr_order_number
        FROM web_returns, ws_wh
        WHERE wr_order_number = ws_wh.ws_order_number
      );

-- 可选：验证结果等价
\echo === Validate equality ===
WITH a AS (
  SELECT ws_order_number FROM ws1 WHERE ws_order_number IN (SELECT ws_order_number FROM ws_wh)
   AND ws_order_number IN (SELECT wr_order_number FROM web_returns, ws_wh WHERE wr_order_number = ws_wh.ws_order_number)
),
 b AS (
  SELECT ws_order_number FROM ws1 WHERE ws_order_number IN (SELECT wr_order_number FROM web_returns, ws_wh WHERE wr_order_number = ws_wh.ws_order_number)
)
SELECT (SELECT count(*) FROM a) AS cnt_a,
       (SELECT count(*) FROM b) AS cnt_b,
       (SELECT count(*) FROM (SELECT * FROM a EXCEPT SELECT * FROM b) s) AS a_minus_b,
       (SELECT count(*) FROM (SELECT * FROM b EXCEPT SELECT * FROM a) s) AS b_minus_a;

-- 清理（如需保留用于多次比较，可注释掉）
-- DROP TABLE ws1; DROP TABLE web_returns; DROP TABLE ws_wh;
\echo === Done (PostgreSQL Q95 in-subset) ===
