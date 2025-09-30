-- PostgreSQL Inequality Constraint Propagation Tests
-- 测试 PostgreSQL 优化器基于不等式约束的范围推理能力

-- 创建测试表
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE customers (
    customer_id INTEGER PRIMARY KEY,
    customer_name VARCHAR(100),
    registration_date DATE,
    credit_limit NUMERIC,
    region VARCHAR(50)
);

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    order_date DATE,
    total_amount NUMERIC,
    status VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    product_name VARCHAR(100),
    price NUMERIC,
    category VARCHAR(50),
    launch_date DATE
);

-- 插入测试数据
INSERT INTO customers VALUES (1, 'Alice', '2020-01-15', 5000, 'North');
INSERT INTO customers VALUES (2, 'Bob', '2021-03-20', 3000, 'South');
INSERT INTO customers VALUES (3, 'Charlie', '2022-06-10', 8000, 'East');
INSERT INTO customers VALUES (4, 'Diana', '2023-01-05', 2000, 'West');
INSERT INTO customers VALUES (5, 'Eve', '2023-12-01', 6000, 'North');

INSERT INTO orders VALUES (101, 1, '2023-02-15', 1500, 'completed');
INSERT INTO orders VALUES (102, 2, '2023-03-25', 800, 'pending');
INSERT INTO orders VALUES (103, 3, '2023-04-10', 2200, 'completed');
INSERT INTO orders VALUES (104, 1, '2023-05-20', 900, 'shipped');
INSERT INTO orders VALUES (105, 4, '2023-06-15', 1200, 'completed');

INSERT INTO products VALUES (201, 'Laptop', 1200, 'Electronics', '2022-01-01');
INSERT INTO products VALUES (202, 'Phone', 800, 'Electronics', '2022-06-01');
INSERT INTO products VALUES (203, 'Book', 30, 'Education', '2021-01-01');
INSERT INTO products VALUES (204, 'Chair', 200, 'Furniture', '2022-03-01');

-- 创建索引
CREATE INDEX idx_customers_reg_date ON customers(registration_date);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_products_launch ON products(launch_date);
CREATE INDEX idx_products_price ON products(price);

-- 收集统计信息
ANALYZE customers;
ANALYZE orders;
ANALYZE products;

-- 测试1: 基本不等式约束推理
-- PostgreSQL 优化器应该能推理出 customers.registration_date < '2023-02-01'
\echo === Test 1: Basic Inequality Constraint Propagation ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, c.registration_date, o.order_date, o.total_amount
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date <= '2023-02-01'
  AND c.registration_date < o.order_date;

-- 测试2: 多表连接的范围推理
-- 优化器应该能推理出 products.launch_date < '2023-02-01'
\echo === Test 2: Multi-table Range Inference ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date, p.product_name, p.launch_date
FROM customers c, orders o, products p
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date
  AND p.launch_date < o.order_date;

-- 测试3: BETWEEN 约束的推理
-- 优化器应该能推理出 customers.credit_limit 的范围
\echo === Test 3: BETWEEN Constraint Inference ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, c.credit_limit, o.total_amount
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.total_amount BETWEEN 1000 AND 2000
  AND c.credit_limit >= o.total_amount;

-- 测试4: 复杂不等式链式推理
-- 优化器应该能推理出多层约束关系
\echo === Test 4: Complex Inequality Chain ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, c.registration_date, o.order_date, p.launch_date
FROM customers c, orders o, products p
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-03-01'
  AND c.registration_date < o.order_date
  AND p.launch_date < o.order_date
  AND p.price > 500
  AND c.credit_limit > p.price;

-- 测试5: 函数约束的推理
-- 测试优化器对函数约束的处理能力
\echo === Test 5: Function Constraint Inference ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= CURRENT_DATE - INTERVAL '12 months'
  AND c.registration_date < o.order_date
  AND EXTRACT(YEAR FROM o.order_date) = 2023;

-- 测试6: 子查询中的约束推理
-- 测试子查询中的约束如何影响外层查询
\echo === Test 6: Subquery Constraint Inference ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, c.registration_date
FROM customers c
WHERE c.registration_date < (
    SELECT MIN(o.order_date)
    FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.order_date >= '2023-02-01'
);

-- 测试7: 分区表的约束推理
-- 创建分区表测试分区裁剪
\echo === Test 7: Partitioned Table Constraint Inference ===
CREATE TABLE orders_partitioned (
    order_id INTEGER,
    customer_id INTEGER,
    order_date DATE,
    total_amount NUMERIC,
    status VARCHAR(20)
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2022 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');
CREATE TABLE orders_2023_q1 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2023-04-01');
CREATE TABLE orders_2023_q2 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-04-01') TO ('2023-07-01');
CREATE TABLE orders_2023_q3 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-07-01') TO ('2023-10-01');
CREATE TABLE orders_2023_q4 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2023-10-01') TO ('2024-01-01');

-- 插入分区数据
INSERT INTO orders_partitioned SELECT * FROM orders;

-- 收集分区表统计信息
ANALYZE orders_partitioned;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, op.order_date, op.total_amount
FROM customers c, orders_partitioned op
WHERE c.customer_id = op.customer_id
  AND op.order_date >= '2023-02-01'
  AND c.registration_date < op.order_date;

-- 测试8: 约束推理的统计信息依赖
-- 测试统计信息对约束推理的影响
\echo === Test 8: Statistics Dependency ===
-- 删除统计信息
DELETE FROM pg_statistic WHERE starelid IN (
    SELECT oid FROM pg_class WHERE relname IN ('customers', 'orders')
);

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date;

-- 重新收集统计信息
ANALYZE customers;
ANALYZE orders;

-- 测试9: 约束推理的性能影响
-- 比较有无约束推理的查询性能
\echo === Test 9: Performance Impact ===
\timing on

-- 有约束推理的查询
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*)
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date;

-- 测试10: 约束推理的边界情况
-- 测试空结果集、NULL值等边界情况
\echo === Test 10: Edge Cases ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2025-01-01'  -- 未来日期，应该无结果
  AND c.registration_date < o.order_date;

-- 测试11: PostgreSQL 特有的约束排除
-- 测试约束排除优化
\echo === Test 11: Constraint Exclusion ===
-- 创建带约束的表
CREATE TABLE orders_with_constraints (
    order_id INTEGER,
    customer_id INTEGER,
    order_date DATE CHECK (order_date >= '2020-01-01'),
    total_amount NUMERIC CHECK (total_amount > 0),
    status VARCHAR(20)
);

INSERT INTO orders_with_constraints SELECT * FROM orders;

-- 启用约束排除
SET constraint_exclusion = on;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*)
FROM orders_with_constraints
WHERE order_date >= '2023-01-01'
  AND total_amount > 1000;

-- 测试12: 表达式索引的约束推理
-- 测试基于表达式的约束推理
\echo === Test 12: Expression Index Constraint Inference ===
CREATE INDEX idx_orders_year ON orders(EXTRACT(YEAR FROM order_date));

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND EXTRACT(YEAR FROM o.order_date) = 2023
  AND c.registration_date < o.order_date;

-- 测试13: 部分索引的约束推理
-- 测试部分索引对约束推理的影响
\echo === Test 13: Partial Index Constraint Inference ===
CREATE INDEX idx_orders_recent ON orders(order_date) 
WHERE order_date >= '2023-01-01';

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date;

-- 测试14: 多列约束的推理
-- 测试复合约束条件的推理
\echo === Test 14: Multi-column Constraint Inference ===
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date, o.total_amount
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date
  AND o.total_amount > 1000;

-- 测试15: 窗口函数的约束推理
-- 测试窗口函数中的约束推理
\echo === Test 15: Window Function Constraint Inference ===
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT c.customer_name, o.order_date, o.total_amount,
       ROW_NUMBER() OVER (PARTITION BY c.customer_id ORDER BY o.order_date) as rn
FROM customers c, orders o
WHERE c.customer_id = o.customer_id
  AND o.order_date >= '2023-02-01'
  AND c.registration_date < o.order_date;

-- 清理
DROP TABLE orders_partitioned CASCADE;
DROP TABLE orders_with_constraints CASCADE;
DROP TABLE products CASCADE;
DROP TABLE orders CASCADE;
DROP TABLE customers CASCADE;

\echo === PostgreSQL Inequality Constraint Propagation Tests Completed ===
