-- Oracle: TPC-DS Q95 风格的 IN 子查询子集裁剪示例
-- 条件2 的结果集合包含在条件1之内，条件1可裁剪

PROMPT === Setup ===
BEGIN EXECUTE IMMEDIATE DROP TABLE web_returns PURGE; EXCEPTION WHEN OTHERS THEN NULL; END; /
BEGIN EXECUTE IMMEDIATE DROP TABLE ws_wh PURGE; EXCEPTION WHEN OTHERS THEN NULL; END; /
BEGIN EXECUTE IMMEDIATE DROP TABLE ws1 PURGE; EXCEPTION WHEN OTHERS THEN NULL; END; /

CREATE TABLE ws_wh(
  ws_order_number NUMBER PRIMARY KEY
);

CREATE TABLE web_returns(
  wr_order_number NUMBER NOT NULL
);

CREATE TABLE ws1(
  ws_order_number NUMBER NOT NULL
);

-- 数据：ws_wh = 1..200000；web_returns = 偶数；ws1 = 随机采样
INSERT /*+ APPEND */ INTO ws_wh SELECT LEVEL FROM dual CONNECT BY LEVEL <= 200000;
INSERT /*+ APPEND */ INTO web_returns SELECT LEVEL*2 FROM dual CONNECT BY LEVEL <= 100000;
COMMIT;

BEGIN
  FOR i IN 1..100000 LOOP
    INSERT INTO ws1 VALUES (TRUNC(DBMS_RANDOM.VALUE(1,200001)));
  END LOOP; COMMIT;
END;
/

BEGIN DBMS_STATS.GATHER_TABLE_STATS(USER, WS1); DBMS_STATS.GATHER_TABLE_STATS(USER, WS_WH); DBMS_STATS.GATHER_TABLE_STATS(USER, WEB_RETURNS); END; /
CREATE INDEX idx_ws1_order ON ws1(ws_order_number);
CREATE INDEX idx_wr_order ON web_returns(wr_order_number);

PROMPT === Query A: 同时包含“超集”与“子集”的 IN 条件 ===
EXPLAIN PLAN FOR
SELECT count(*)
FROM ws1
WHERE ws_order_number IN (SELECT ws_order_number FROM ws_wh)
  AND ws_order_number IN (
        SELECT wr_order_number
        FROM web_returns, ws_wh
        WHERE wr_order_number = ws_wh.ws_order_number
      );
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

PROMPT === Query B: 仅保留“子集”条件（与 A 结果应等价） ===
EXPLAIN PLAN FOR
SELECT count(*)
FROM ws1
WHERE ws_order_number IN (
        SELECT wr_order_number
        FROM web_returns, ws_wh
        WHERE wr_order_number = ws_wh.ws_order_number
      );
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

PROMPT === 校验等价性（行数应相同） ===
SELECT (SELECT COUNT(*) FROM ws1 WHERE ws_order_number IN (SELECT ws_order_number FROM ws_wh)
                                 AND ws_order_number IN (SELECT wr_order_number FROM web_returns, ws_wh WHERE wr_order_number = ws_wh.ws_order_number)) AS cnt_a,
       (SELECT COUNT(*) FROM ws1 WHERE ws_order_number IN (SELECT wr_order_number FROM web_returns, ws_wh WHERE wr_order_number = ws_wh.ws_order_number)) AS cnt_b
FROM dual;

-- 清理（可选）
-- DROP TABLE ws1 PURGE; DROP TABLE web_returns PURGE; DROP TABLE ws_wh PURGE;
PROMPT === Done (Oracle Q95 in-subset) ===
