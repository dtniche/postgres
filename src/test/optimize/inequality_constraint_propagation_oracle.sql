-- Oracle Inequality Constraint Propagation Tests
-- 测试 Oracle 优化器基于不等式约束的范围推理能力

-- 创建测试表
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE customers (
    customer_id NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100),
    registration_date DATE,
    credit_limit NUMBER,
    region VARCHAR2(50)
);

CREATE TABLE orders (
    order_id NUMBER PRIMARY KEY,
    customer_id NUMBER,
    order_date DATE,
    total_amount NUMBER,
    status VARCHAR2(20),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE products (
    product_id NUMBER PRIMARY KEY,
    product_name VARCHAR2(100),
    price NUMBER,
    category VARCHAR2(50),
    launch_date DATE
);

-- 插入测试数据
INSERT INTO customers VALUES (1, 'Alice', DATE '2020-01-15', 5000, 'North');
INSERT INTO customers VALUES (2, 'Bob', DATE '2021-03-20', 3000, 'South');
INSERT INTO customers VALUES (3, 'Charlie', DATE '2022-06-10', 8000, 'East');
INSERT INTO customers VALUES (4, 'Diana', DATE '2023-01-05', 2000, 'West');
INSERT INTO customers VALUES (5, 'Eve', DATE '2023-12-01', 6000, 'North');

INSERT INTO orders VALUES (101, 1, DATE '2023-02-15', 1500, 'completed');
INSERT INTO orders VALUES (102, 2, DATE '2023-03-25', 800, 'pending');
INSERT INTO orders VALUES (103, 3, DATE '2023-04-10', 2200, 'completed');
INSERT INTO orders VALUES (104, 1, DATE '2023-05-20', 900, 'shipped');
INSERT INTO orders VALUES (105, 4, DATE '2023-06-15', 1200, 'completed');

INSERT INTO products VALUES (201, 'Laptop', 1200, 'Electronics', DATE '2022-01-01');
INSERT INTO products VALUES (202, 'Phone', 800, 'Electronics', DATE '2022-06-01');
INSERT INTO products VALUES (203, 'Book', 30, 'Education', DATE '2021-01-01');
INSERT INTO products VALUES (204, 'Chair', 200, 'Furniture', DATE '2022-03-01');

COMMIT;

-- 创建索引
CREATE INDEX idx_customers_reg_date ON customers(registration_date);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_products_launch ON products(launch_date);
CREATE INDEX idx_products_price ON products(price);

-- 收集统计信息
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUSTOMERS');
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ORDERS');
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'PRODUCTS');

-- 测试1: 基本不等式约束推理
-- 优化器应该能推理出 customers.registration_date < '2023-02-01'
PROMPT === Test 1: Basic Inequality Constraint Propagation ===
EXPLAIN PLAN FOR
SELECT c.customer_name, c.registration_date, o.order_date, o.total_amount
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date <= DATE '2023-02-01'
  AND c.registration_date < o.order_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试2: 多表连接的范围推理
-- 优化器应该能推理出 products.launch_date < '2023-02-01'
PROMPT === Test 2: Multi-table Range Inference ===
EXPLAIN PLAN FOR
SELECT c.customer_name, o.order_date, p.product_name, p.launch_date
FROM customers c, orders o, products p
WHERE c.customer_id = o.customer_id
  AND o.order_date >= DATE '2023-02-01'
  AND c.registration_date < o.order_date
  AND p.launch_date < o.order_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试3: BETWEEN 约束的推理
-- 优化器应该能推理出 customers.credit_limit 的范围
PROMPT === Test 3: BETWEEN Constraint Inference ===
EXPLAIN PLAN FOR
SELECT c.customer_name, c.credit_limit, o.total_amount
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.total_amount BETWEEN 1000 AND 2000
  AND c.credit_limit >= o.total_amount;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试4: 复杂不等式链式推理
-- 优化器应该能推理出多层约束关系
PROMPT === Test 4: Complex Inequality Chain ===
EXPLAIN PLAN FOR
SELECT c.customer_name, c.registration_date, o.order_date, p.launch_date
FROM customers c, orders o, products p
WHERE c.customer_id = o.customer_id
  AND o.order_date >= DATE '2023-03-01'
  AND c.registration_date < o.order_date
  AND p.launch_date < o.order_date
  AND p.price > 500
  AND c.credit_limit > p.price;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试5: 函数约束的推理
-- 测试优化器对函数约束的处理能力
PROMPT === Test 5: Function Constraint Inference ===
EXPLAIN PLAN FOR
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= ADD_MONTHS(SYSDATE, -12)
  AND c.registration_date < o.order_date
  AND EXTRACT(YEAR FROM o.order_date) = 2023;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试6: 子查询中的约束推理
-- 测试子查询中的约束如何影响外层查询
PROMPT === Test 6: Subquery Constraint Inference ===
EXPLAIN PLAN FOR
SELECT c.customer_name, c.registration_date
FROM customers c
WHERE c.registration_date < (
    SELECT MIN(o.order_date)
    FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.order_date >= DATE '2023-02-01'
);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试7: 分区表的约束推理
-- 创建分区表测试分区裁剪
PROMPT === Test 7: Partitioned Table Constraint Inference ===
CREATE TABLE orders_partitioned (
    order_id NUMBER,
    customer_id NUMBER,
    order_date DATE,
    total_amount NUMBER,
    status VARCHAR2(20)
) PARTITION BY RANGE (order_date) (
    PARTITION p2022 VALUES LESS THAN (DATE '2023-01-01'),
    PARTITION p2023_q1 VALUES LESS THAN (DATE '2023-04-01'),
    PARTITION p2023_q2 VALUES LESS THAN (DATE '2023-07-01'),
    PARTITION p2023_q3 VALUES LESS THAN (DATE '2023-10-01'),
    PARTITION p2023_q4 VALUES LESS THAN (DATE '2024-01-01')
);

-- 插入分区数据
INSERT INTO orders_partitioned SELECT * FROM orders;
COMMIT;

EXPLAIN PLAN FOR
SELECT c.customer_name, op.order_date, op.total_amount
FROM customers c, orders_partitioned op
WHERE c.customer_id = op.customer_id
  AND op.order_date >= DATE '2023-02-01'
  AND c.registration_date < op.order_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 测试8: 约束推理的统计信息依赖
-- 测试统计信息对约束推理的影响
PROMPT === Test 8: Statistics Dependency ===
-- 删除统计信息
EXEC DBMS_STATS.DELETE_TABLE_STATS(USER, 'CUSTOMERS');
EXEC DBMS_STATS.DELETE_TABLE_STATS(USER, 'ORDERS');

EXPLAIN PLAN FOR
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= DATE '2023-02-01'
  AND c.registration_date < o.order_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 重新收集统计信息
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUSTOMERS');
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'ORDERS');

-- 测试9: 约束推理的性能影响
-- 比较有无约束推理的查询性能
PROMPT === Test 9: Performance Impact ===
SET TIMING ON;

-- 有约束推理的查询
SELECT /*+ GATHER_PLAN_STATISTICS */ COUNT(*)
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= DATE '2023-02-01'
  AND c.registration_date < o.order_date;

-- 查看执行统计
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(FORMAT => 'ALLSTATS LAST'));

-- 测试10: 约束推理的边界情况
-- 测试空结果集、NULL值等边界情况
PROMPT === Test 10: Edge Cases ===
EXPLAIN PLAN FOR
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= DATE '2025-01-01'  -- 未来日期，应该无结果
  AND c.registration_date < o.order_date;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 清理
DROP TABLE orders_partitioned;
DROP TABLE products;
DROP TABLE orders;
DROP TABLE customers;

PROMPT === Oracle Inequality Constraint Propagation Tests Completed ===
