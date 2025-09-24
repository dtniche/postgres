#!/usr/bin/env python3
"""
Oracle DBA_ALL_TABLES 字段内容分析脚本
用于获取Oracle实际数据，对比PostgreSQL实现
"""

import cx_Oracle
import json
from datetime import datetime

def connect_oracle():
    """连接Oracle数据库"""
    try:
        dsn = cx_Oracle.makedsn('172.23.160.1', 1521, service_name='XEPDB1')
        connection = cx_Oracle.connect('sys', '111111', dsn, mode=cx_Oracle.SYSDBA)
        print("Oracle连接成功")
        return connection
    except Exception as e:
        print(f"Oracle连接失败: {e}")
        return None

def get_oracle_field_values(connection):
    """获取Oracle DBA_ALL_TABLES的字段值分布"""
    cursor = connection.cursor()
    
    # 查询关键字段的值分布
    queries = {
        'status': "SELECT DISTINCT status FROM dba_all_tables ORDER BY status",
        'logging': "SELECT DISTINCT logging FROM dba_all_tables ORDER BY logging", 
        'backed_up': "SELECT DISTINCT backed_up FROM dba_all_tables ORDER BY backed_up",
        'temporary': "SELECT DISTINCT temporary FROM dba_all_tables ORDER BY temporary",
        'buffer_pool': "SELECT DISTINCT buffer_pool FROM dba_all_tables ORDER BY buffer_pool",
        'compression': "SELECT DISTINCT compression FROM dba_all_tables ORDER BY compression",
        'partitioned': "SELECT DISTINCT partitioned FROM dba_all_tables ORDER BY partitioned",
        'inmemory': "SELECT DISTINCT inmemory FROM dba_all_tables ORDER BY inmemory",
        'external': "SELECT DISTINCT external FROM dba_all_tables ORDER BY external",
        'segment_created': "SELECT DISTINCT segment_created FROM dba_all_tables ORDER BY segment_created",
        'global_stats': "SELECT DISTINCT global_stats FROM dba_all_tables ORDER BY global_stats",
        'user_stats': "SELECT DISTINCT user_stats FROM dba_all_tables ORDER BY user_stats",
        'monitoring': "SELECT DISTINCT monitoring FROM dba_all_tables ORDER BY monitoring",
        'row_movement': "SELECT DISTINCT row_movement FROM dba_all_tables ORDER BY row_movement"
    }
    
    results = {}
    
    for field_name, query in queries.items():
        try:
            cursor.execute(query)
            values = [row[0] for row in cursor.fetchall()]
            results[field_name] = values
            print(f"{field_name}: {values}")
        except Exception as e:
            print(f"查询 {field_name} 失败: {e}")
            results[field_name] = []
    
    return results

def get_sample_data(connection):
    """获取样本数据"""
    cursor = connection.cursor()
    
    query = """
    SELECT 
        owner, table_name, tablespace_name, status, logging, backed_up,
        temporary, buffer_pool, compression, partitioned, inmemory, external,
        segment_created, global_stats, user_stats, monitoring, row_movement,
        num_rows, blocks, pct_free, pct_used
    FROM dba_all_tables 
    WHERE rownum <= 10
    ORDER BY owner, table_name
    """
    
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        
        sample_data = []
        for row in rows:
            sample_data.append({
                'owner': row[0],
                'table_name': row[1], 
                'tablespace_name': row[2],
                'status': row[3],
                'logging': row[4],
                'backed_up': row[5],
                'temporary': row[6],
                'buffer_pool': row[7],
                'compression': row[8],
                'partitioned': row[9],
                'inmemory': row[10],
                'external': row[11],
                'segment_created': row[12],
                'global_stats': row[13],
                'user_stats': row[14],
                'monitoring': row[15],
                'row_movement': row[16],
                'num_rows': row[17],
                'blocks': row[18],
                'pct_free': row[19],
                'pct_used': row[20]
            })
        
        return sample_data
    except Exception as e:
        print(f"获取样本数据失败: {e}")
        return []

def get_null_value_stats(connection):
    """获取NULL值统计"""
    cursor = connection.cursor()
    
    query = """
    SELECT 
        COUNT(*) as total_tables,
        COUNT(tablespace_name) as tablespace_name_not_null,
        COUNT(cluster_name) as cluster_name_not_null,
        COUNT(iot_name) as iot_name_not_null,
        COUNT(pct_used) as pct_used_not_null,
        COUNT(ini_trans) as ini_trans_not_null,
        COUNT(max_trans) as max_trans_not_null,
        COUNT(initial_extent) as initial_extent_not_null,
        COUNT(next_extent) as next_extent_not_null,
        COUNT(min_extents) as min_extents_not_null,
        COUNT(max_extents) as max_extents_not_null,
        COUNT(pct_increase) as pct_increase_not_null,
        COUNT(freelists) as freelists_not_null,
        COUNT(freelist_groups) as freelist_groups_not_null
    FROM dba_all_tables
    """
    
    try:
        cursor.execute(query)
        row = cursor.fetchone()
        return {
            'total_tables': row[0],
            'tablespace_name_not_null': row[1],
            'cluster_name_not_null': row[2],
            'iot_name_not_null': row[3],
            'pct_used_not_null': row[4],
            'ini_trans_not_null': row[5],
            'max_trans_not_null': row[6],
            'initial_extent_not_null': row[7],
            'next_extent_not_null': row[8],
            'min_extents_not_null': row[9],
            'max_extents_not_null': row[10],
            'pct_increase_not_null': row[11],
            'freelists_not_null': row[12],
            'freelist_groups_not_null': row[13]
        }
    except Exception as e:
        print(f"获取NULL值统计失败: {e}")
        return {}

def main():
    """主函数"""
    print("开始分析Oracle DBA_ALL_TABLES字段内容...")
    
    connection = connect_oracle()
    if not connection:
        return
    
    try:
        # 获取字段值分布
        print("\n=== 字段值分布 ===")
        field_values = get_oracle_field_values(connection)
        
        # 获取样本数据
        print("\n=== 样本数据 ===")
        sample_data = get_sample_data(connection)
        for i, data in enumerate(sample_data, 1):
            print(f"\n样本 {i}:")
            for key, value in data.items():
                print(f"  {key}: {value}")
        
        # 获取NULL值统计
        print("\n=== NULL值统计 ===")
        null_stats = get_null_value_stats(connection)
        for key, value in null_stats.items():
            print(f"  {key}: {value}")
        
        # 保存结果到JSON文件
        result = {
            'timestamp': datetime.now().isoformat(),
            'field_values': field_values,
            'sample_data': sample_data,
            'null_stats': null_stats
        }
        
        with open('oracle_field_analysis.json', 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        
        print("\n分析结果已保存到: oracle_field_analysis.json")
        
    except Exception as e:
        print(f"分析过程中出错: {e}")
    
    finally:
        connection.close()
        print("Oracle连接已关闭")

if __name__ == '__main__':
    main()
