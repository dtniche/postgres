#!/usr/bin/env python3
"""
PostgreSQL 查询优化基准测试
测试不同数据规模下的优化效果
"""

import os
import subprocess
import sys
import time
import json
import statistics
from typing import List, Dict, Tuple
import getpass


class QueryBenchmark:
    """查询性能基准测试类"""
    
    def __init__(self, host: str = '127.0.0.1', dbname: str = 'postgres', 
                 user: str = None, password: str = None):
        self.host = host
        self.dbname = dbname
        self.user = user or os.environ.get('PGUSER') or getpass.getuser()
        self.password = password or os.environ.get('PGPASSWORD')
        self.env = os.environ.copy()
        if self.password:
            self.env['PGPASSWORD'] = self.password
        self.env['LC_ALL'] = 'C'
    
    def execute_sql(self, sql: str, timeout: int = 300) -> Tuple[bool, str, str]:
        """执行 SQL 并返回结果"""
        cmd = ['psql', '-h', self.host, '-U', self.user, '-d', self.dbname, '-c', sql]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, 
                                  env=self.env, timeout=timeout)
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Query timed out"
        except Exception as e:
            return False, "", str(e)
    
    def create_test_data(self, table_size: int) -> bool:
        """创建指定大小的测试数据"""
        print(f"创建测试数据 (表大小: {table_size:,} 行)...")
        
        # 清理
        cleanup_sql = "DROP TABLE IF EXISTS t1 CASCADE; DROP TABLE IF EXISTS t2 CASCADE;"
        self.execute_sql(cleanup_sql)
        
        # 创建表和数据
        create_sql = f"""
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
        
        INSERT INTO t1 (a, b, data) 
        SELECT 
            (random() * 1000)::INTEGER,
            (random() * 1000)::INTEGER,
            'data_' || generate_series
        FROM generate_series(1, {table_size});
        
        INSERT INTO t2 (a, b, data)
        SELECT 
            (random() * 1000)::INTEGER,
            (random() * 1000)::INTEGER,
            'data_' || generate_series
        FROM generate_series(1, {table_size});
        
        CREATE INDEX idx_t1_a ON t1(a);
        CREATE INDEX idx_t1_b ON t1(b);
        CREATE INDEX idx_t2_a ON t2(a);
        CREATE INDEX idx_t2_b ON t2(b);
        
        ANALYZE t1;
        ANALYZE t2;
        """
        
        success, _, error = self.execute_sql(create_sql)
        if not success:
            print(f"创建测试数据失败: {error}")
            return False
        
        print("✅ 测试数据创建成功")
        return True
    
    def run_query_multiple_times(self, sql: str, query_name: str, runs: int = 3) -> Dict:
        """多次运行查询并计算统计信息"""
        print(f"运行查询: {query_name} ({runs} 次)")
        
        execution_times = []
        planning_times = []
        
        for i in range(runs):
            explain_sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}"
            success, result, error = self.execute_sql(explain_sql)
            
            if not success:
                print(f"查询执行失败: {error}")
                continue
            
            try:
                plan_data = json.loads(result)
                exec_time = plan_data[0]['Execution Time']
                plan_time = plan_data[0]['Planning Time']
                
                execution_times.append(exec_time)
                planning_times.append(plan_time)
                
                print(f"  运行 {i+1}: 执行时间 {exec_time:.2f}ms, 规划时间 {plan_time:.2f}ms")
                
            except (json.JSONDecodeError, KeyError) as e:
                print(f"  运行 {i+1}: 解析失败 - {e}")
                continue
        
        if not execution_times:
            return {}
        
        return {
            'query_name': query_name,
            'execution_times': execution_times,
            'planning_times': planning_times,
            'avg_execution_time': statistics.mean(execution_times),
            'median_execution_time': statistics.median(execution_times),
            'min_execution_time': min(execution_times),
            'max_execution_time': max(execution_times),
            'std_execution_time': statistics.stdev(execution_times) if len(execution_times) > 1 else 0,
            'avg_planning_time': statistics.mean(planning_times),
            'runs': len(execution_times)
        }
    
    def run_benchmark(self, table_sizes: List[int] = [1000, 5000, 10000, 20000]) -> Dict:
        """运行不同数据规模的基准测试"""
        print("开始基准测试...")
        print("="*80)
        
        # 定义测试查询
        queries = {
            "原始查询": """
                SELECT * FROM t1 WHERE
                EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a OR t1.b = t2.b)
            """,
            "优化查询": """
                SELECT * FROM t1 WHERE
                EXISTS (SELECT 1 FROM t2 WHERE t1.a = t2.a)
                OR
                EXISTS (SELECT 1 FROM t2 WHERE t1.b = t2.b)
            """
        }
        
        results = {}
        
        for table_size in table_sizes:
            print(f"\n测试数据规模: {table_size:,} 行")
            print("-" * 50)
            
            if not self.create_test_data(table_size):
                print(f"❌ 无法创建 {table_size} 行的测试数据，跳过")
                continue
            
            size_results = {}
            
            for query_name, sql in queries.items():
                result = self.run_query_multiple_times(sql, query_name, runs=3)
                if result:
                    size_results[query_name] = result
                    print(f"  {query_name}: 平均执行时间 {result['avg_execution_time']:.2f}ms")
            
            if size_results:
                results[table_size] = size_results
                
                # 计算性能提升
                if "原始查询" in size_results and "优化查询" in size_results:
                    original_time = size_results["原始查询"]['avg_execution_time']
                    optimized_time = size_results["优化查询"]['avg_execution_time']
                    improvement = (original_time - optimized_time) / original_time * 100
                    print(f"  🚀 性能提升: {improvement:.1f}%")
        
        return results
    
    def generate_report(self, results: Dict) -> None:
        """生成基准测试报告"""
        print("\n" + "="*80)
        print("基准测试报告")
        print("="*80)
        
        if not results:
            print("❌ 没有测试结果")
            return
        
        # 创建性能对比表
        print("\n📊 性能对比表:")
        print("-" * 80)
        print(f"{'数据规模':<12} {'原始查询(ms)':<15} {'优化查询(ms)':<15} {'性能提升':<12}")
        print("-" * 80)
        
        for table_size, size_results in results.items():
            if "原始查询" in size_results and "优化查询" in size_results:
                original = size_results["原始查询"]['avg_execution_time']
                optimized = size_results["优化查询"]['avg_execution_time']
                improvement = (original - optimized) / original * 100
                
                print(f"{table_size:<12,} {original:<15.2f} {optimized:<15.2f} {improvement:<12.1f}%")
        
        # 分析趋势
        print("\n📈 性能趋势分析:")
        print("-" * 50)
        
        improvements = []
        for table_size, size_results in results.items():
            if "原始查询" in size_results and "优化查询" in size_results:
                original = size_results["原始查询"]['avg_execution_time']
                optimized = size_results["优化查询"]['avg_execution_time']
                improvement = (original - optimized) / original * 100
                improvements.append((table_size, improvement))
        
        if improvements:
            avg_improvement = statistics.mean([imp[1] for imp in improvements])
            max_improvement = max(improvements, key=lambda x: x[1])
            min_improvement = min(improvements, key=lambda x: x[1])
            
            print(f"平均性能提升: {avg_improvement:.1f}%")
            print(f"最大性能提升: {max_improvement[1]:.1f}% (数据规模: {max_improvement[0]:,} 行)")
            print(f"最小性能提升: {min_improvement[1]:.1f}% (数据规模: {min_improvement[0]:,} 行)")
        
        # 优化建议
        print("\n💡 优化建议:")
        print("-" * 50)
        print("1. 对于大数据集，优化效果更加明显")
        print("2. 确保相关列上有适当的索引")
        print("3. 定期更新表统计信息")
        print("4. 考虑使用分区表处理超大数据集")
        print("5. 监控查询性能并持续优化")
    
    def cleanup(self) -> None:
        """清理测试环境"""
        print("\n清理测试环境...")
        cleanup_sql = "DROP TABLE IF EXISTS t1 CASCADE; DROP TABLE IF EXISTS t2 CASCADE;"
        success, _, error = self.execute_sql(cleanup_sql)
        if success:
            print("✅ 测试环境清理完成")
        else:
            print(f"⚠️ 清理时出现警告: {error}")


def main():
    """主函数"""
    print("PostgreSQL 查询优化基准测试")
    print("测试不同数据规模下的优化效果")
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
    
    # 创建基准测试实例
    benchmark = QueryBenchmark(host, dbname, user, password)
    
    try:
        # 运行基准测试
        results = benchmark.run_benchmark([1000, 5000, 10000, 20000])
        
        # 生成报告
        benchmark.generate_report(results)
        
        print("\n✅ 基准测试完成!")
        
    except KeyboardInterrupt:
        print("\n⚠️ 测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试过程中出现错误: {e}")
        return 1
    finally:
        # 清理测试环境
        benchmark.cleanup()
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
