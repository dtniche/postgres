#!/usr/bin/env python3
"""
PostgreSQL 查询优化示例：EXISTS 子查询中的 OR 条件重写优化

这个脚本演示了如何通过重写 EXISTS 子查询中的 OR 条件来优化查询性能，
将 Nested Loop Join 优化为 Hash Join，从而获得显著的性能提升。

作者: AI Assistant
日期: 2024
"""

import os
import subprocess
import sys
import time
import json
from typing import Dict, List, Tuple, Optional
import getpass


class PostgreSQLQueryOptimizer:
    """PostgreSQL 查询优化器测试类"""
    
    def __init__(self, host: str = '127.0.0.1', dbname: str = 'postgres', 
                 user: Optional[str] = None, password: Optional[str] = None):
        """初始化数据库连接参数"""
        self.host = host
        self.dbname = dbname
        self.user = user or os.environ.get('PGUSER') or getpass.getuser()
        self.password = password or os.environ.get('PGPASSWORD')
        self.env = os.environ.copy()
        if self.password:
            self.env['PGPASSWORD'] = self.password
        self.env['LC_ALL'] = 'C'
    
    def execute_sql(self, sql: str, timeout: int = 60) -> Tuple[bool, str, str]:
        """执行 SQL 语句并返回结果"""
        cmd = ['psql', '-h', self.host, '-U', self.user, '-d', self.dbname, '-c', sql]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, 
                                  env=self.env, timeout=timeout)
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", "SQL execution timed out"
        except Exception as e:
            return False, "", str(e)
    
    def create_test_environment(self, table_size: int = 10000) -> bool:
        """创建测试环境和数据"""
        print(f"创建测试环境 (表大小: {table_size:,} 行)...")
        
        # 清理现有表
        cleanup_sql = """
        DROP TABLE IF EXISTS customers CASCADE;
        DROP TABLE IF EXISTS orders CASCADE;
        DROP TABLE IF EXISTS products CASCADE;
        """
        
        success, _, error = self.execute_sql(cleanup_sql)
        if not success:
            print(f"清理表失败: {error}")
            return False
        
        # 创建测试表
        create_sql = f"""
        -- 创建客户表
        CREATE TABLE customers (
            customer_id SERIAL PRIMARY KEY,
            name VARCHAR(100),
            email VARCHAR(100),
            phone VARCHAR(20),
            region VARCHAR(50),
            created_date DATE
        );
        
        -- 创建产品表
        CREATE TABLE products (
            product_id SERIAL PRIMARY KEY,
            name VARCHAR(100),
            category VARCHAR(50),
            price DECIMAL(10,2),
            stock_quantity INTEGER
        );
        
        -- 创建订单表
        CREATE TABLE orders (
            order_id SERIAL PRIMARY KEY,
            customer_id INTEGER,
            product_id INTEGER,
            quantity INTEGER,
            order_date DATE,
            status VARCHAR(20)
        );
        
        -- 插入测试数据
        INSERT INTO customers (name, email, phone, region, created_date)
        SELECT 
            'Customer_' || generate_series,
            'customer' || generate_series || '@example.com',
            '555-' || lpad((random() * 9999)::INTEGER::TEXT, 4, '0'),
            CASE (random() * 4)::INTEGER
                WHEN 0 THEN 'North'
                WHEN 1 THEN 'South' 
                WHEN 2 THEN 'East'
                ELSE 'West'
            END,
            CURRENT_DATE - (random() * 365)::INTEGER
        FROM generate_series(1, {table_size});
        
        INSERT INTO products (name, category, price, stock_quantity)
        SELECT 
            'Product_' || generate_series,
            CASE (random() * 5)::INTEGER
                WHEN 0 THEN 'Electronics'
                WHEN 1 THEN 'Clothing'
                WHEN 2 THEN 'Books'
                WHEN 3 THEN 'Home'
                ELSE 'Sports'
            END,
            (random() * 1000 + 10)::DECIMAL(10,2),
            (random() * 1000)::INTEGER
        FROM generate_series(1, {table_size});
        
        INSERT INTO orders (customer_id, product_id, quantity, order_date, status)
        SELECT 
            (random() * {table_size})::INTEGER + 1,
            (random() * {table_size})::INTEGER + 1,
            (random() * 10)::INTEGER + 1,
            CURRENT_DATE - (random() * 365)::INTEGER,
            CASE (random() * 3)::INTEGER
                WHEN 0 THEN 'pending'
                WHEN 1 THEN 'shipped'
                ELSE 'delivered'
            END
        FROM generate_series(1, {table_size * 2});
        
        -- 创建索引
        CREATE INDEX idx_customers_region ON customers(region);
        CREATE INDEX idx_customers_email ON customers(email);
        CREATE INDEX idx_products_category ON products(category);
        CREATE INDEX idx_products_price ON products(price);
        CREATE INDEX idx_orders_customer_id ON orders(customer_id);
        CREATE INDEX idx_orders_product_id ON orders(product_id);
        CREATE INDEX idx_orders_date ON orders(order_date);
        
        -- 更新统计信息
        ANALYZE customers;
        ANALYZE products;
        ANALYZE orders;
        """
        
        success, _, error = self.execute_sql(create_sql)
        if not success:
            print(f"创建测试环境失败: {error}")
            return False
        
        print("✅ 测试环境创建成功")
        return True
    
    def run_query_analysis(self, query_name: str, sql: str) -> Dict:
        """运行查询并分析执行计划"""
        print(f"\n{'='*60}")
        print(f"分析查询: {query_name}")
        print(f"{'='*60}")
        
        # 获取执行计划
        explain_sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}"
        success, result, error = self.execute_sql(explain_sql)
        
        if not success:
            print(f"❌ 查询执行失败: {error}")
            return {}
        
        try:
            # 解析 JSON 执行计划
            plan_data = json.loads(result)
            plan = plan_data[0]['Plan']
            
            # 提取关键信息
            analysis = {
                'query_name': query_name,
                'execution_time': plan_data[0]['Execution Time'],
                'planning_time': plan_data[0]['Planning Time'],
                'total_cost': plan['Total Cost'],
                'actual_rows': plan['Actual Rows'],
                'actual_loops': plan['Actual Loops'],
                'join_type': self._extract_join_type(plan),
                'buffer_usage': self._extract_buffer_usage(plan),
                'node_type': plan['Node Type']
            }
            
            # 打印执行计划摘要
            print(f"执行时间: {analysis['execution_time']:.2f} ms")
            print(f"规划时间: {analysis['planning_time']:.2f} ms")
            print(f"总成本: {analysis['total_cost']:.2f}")
            print(f"实际行数: {analysis['actual_rows']:,}")
            print(f"连接类型: {analysis['join_type']}")
            print(f"节点类型: {analysis['node_type']}")
            
            return analysis
            
        except (json.JSONDecodeError, KeyError) as e:
            print(f"❌ 解析执行计划失败: {e}")
            print(f"原始结果: {result}")
            return {}
    
    def _extract_join_type(self, plan: Dict) -> str:
        """从执行计划中提取连接类型"""
        node_type = plan.get('Node Type', '')
        if 'Hash' in node_type:
            return 'Hash Join'
        elif 'Nested Loop' in node_type:
            return 'Nested Loop Join'
        elif 'Merge' in node_type:
            return 'Merge Join'
        else:
            return node_type
    
    def _extract_buffer_usage(self, plan: Dict) -> Dict:
        """提取缓冲区使用情况"""
        buffers = plan.get('Buffers', {})
        return {
            'shared_hit': buffers.get('Shared Hit Blocks', 0),
            'shared_read': buffers.get('Shared Read Blocks', 0),
            'shared_dirtied': buffers.get('Shared Dirtied Blocks', 0),
            'shared_written': buffers.get('Shared Written Blocks', 0)
        }
    
    def run_optimization_comparison(self) -> Dict:
        """运行优化对比测试"""
        print("\n" + "="*80)
        print("PostgreSQL 查询优化对比测试")
        print("="*80)
        
        # 定义测试查询
        queries = {
            "原始查询 (OR 条件在 EXISTS 中)": """
                SELECT c.customer_id, c.name, c.email
                FROM customers c
                WHERE EXISTS (
                    SELECT 1 FROM orders o 
                    JOIN products p ON o.product_id = p.product_id
                    WHERE o.customer_id = c.customer_id 
                    AND (p.category = 'Electronics' OR p.price > 500)
                );
            """,
            
            "优化查询 (OR 条件分解)": """
                SELECT c.customer_id, c.name, c.email
                FROM customers c
                WHERE EXISTS (
                    SELECT 1 FROM orders o 
                    JOIN products p ON o.product_id = p.product_id
                    WHERE o.customer_id = c.customer_id 
                    AND p.category = 'Electronics'
                )
                OR EXISTS (
                    SELECT 1 FROM orders o 
                    JOIN products p ON o.product_id = p.product_id
                    WHERE o.customer_id = c.customer_id 
                    AND p.price > 500
                );
            """,
            
            "进一步优化 (使用 UNION)": """
                SELECT DISTINCT c.customer_id, c.name, c.email
                FROM customers c
                WHERE c.customer_id IN (
                    SELECT o.customer_id FROM orders o 
                    JOIN products p ON o.product_id = p.product_id
                    WHERE p.category = 'Electronics'
                    UNION
                    SELECT o.customer_id FROM orders o 
                    JOIN products p ON o.product_id = p.product_id
                    WHERE p.price > 500
                );
            """
        }
        
        results = {}
        
        for query_name, sql in queries.items():
            results[query_name] = self.run_query_analysis(query_name, sql)
            time.sleep(1)  # 避免缓存影响
        
        return results
    
    def analyze_results(self, results: Dict) -> None:
        """分析并展示优化结果"""
        print("\n" + "="*80)
        print("优化结果分析")
        print("="*80)
        
        if not results:
            print("❌ 没有可分析的结果")
            return
        
        # 提取执行时间进行对比
        execution_times = {}
        join_types = {}
        
        for query_name, analysis in results.items():
            if analysis:
                execution_times[query_name] = analysis['execution_time']
                join_types[query_name] = analysis['join_type']
        
        if len(execution_times) < 2:
            print("❌ 结果不足，无法进行对比分析")
            return
        
        # 性能对比
        print("\n📊 性能对比:")
        print("-" * 60)
        for query_name, exec_time in execution_times.items():
            print(f"{query_name:<30}: {exec_time:>8.2f} ms")
        
        # 计算性能提升
        if len(execution_times) >= 2:
            original_time = list(execution_times.values())[0]
            optimized_time = list(execution_times.values())[1]
            improvement = (original_time - optimized_time) / original_time * 100
            
            print(f"\n🚀 性能提升: {improvement:.1f}%")
            print(f"   原始查询: {original_time:.2f} ms")
            print(f"   优化查询: {optimized_time:.2f} ms")
        
        # 连接类型对比
        print("\n🔗 连接类型对比:")
        print("-" * 60)
        for query_name, join_type in join_types.items():
            print(f"{query_name:<30}: {join_type}")
        
        # 优化建议
        print("\n💡 优化建议:")
        print("-" * 60)
        print("1. 将 EXISTS 子查询中的 OR 条件分解为多个独立的 EXISTS")
        print("2. 考虑使用 UNION 来进一步优化复杂查询")
        print("3. 确保相关列上有适当的索引")
        print("4. 定期更新表统计信息 (ANALYZE)")
        print("5. 考虑使用物化视图来预计算复杂查询")
    
    def cleanup(self) -> None:
        """清理测试环境"""
        print("\n清理测试环境...")
        cleanup_sql = """
        DROP TABLE IF EXISTS customers CASCADE;
        DROP TABLE IF EXISTS orders CASCADE;
        DROP TABLE IF EXISTS products CASCADE;
        """
        success, _, error = self.execute_sql(cleanup_sql)
        if success:
            print("✅ 测试环境清理完成")
        else:
            print(f"⚠️ 清理时出现警告: {error}")


def main():
    """主函数"""
    print("PostgreSQL 查询优化示例")
    print("演示 EXISTS 子查询中 OR 条件的优化方法")
    print("="*80)
    
    # 获取连接参数
    host = os.environ.get('PGHOST', '127.0.0.1')
    dbname = os.environ.get('PGDATABASE', 'postgres')
    user = os.environ.get('PGUSER')
    password = os.environ.get('PGPASSWORD')
    
    if not user:
        user = getpass.getuser()
    if not password:
        password = getpass.getpass(f"Password for user {user}: ")
    
    print(f"连接到: {host}:{dbname} (用户: {user})")
    
    # 创建优化器实例
    optimizer = PostgreSQLQueryOptimizer(host, dbname, user, password)
    
    try:
        # 创建测试环境
        if not optimizer.create_test_environment(table_size=5000):
            print("❌ 无法创建测试环境，退出")
            return 1
        
        # 运行优化对比测试
        results = optimizer.run_optimization_comparison()
        
        # 分析结果
        optimizer.analyze_results(results)
        
        print("\n✅ 测试完成!")
        
    except KeyboardInterrupt:
        print("\n⚠️ 测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试过程中出现错误: {e}")
        return 1
    finally:
        # 清理测试环境
        optimizer.cleanup()
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
