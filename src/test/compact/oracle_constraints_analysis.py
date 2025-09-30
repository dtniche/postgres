#!/usr/bin/env python3
"""
Oracle DBA_CONSTRAINTS 字段内容分析脚本
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

def get_oracle_constraints_structure(connection):
    """获取Oracle DBA_CONSTRAINTS的字段结构"""
    cursor = connection.cursor()
    
    # 查询DBA_CONSTRAINTS的字段信息
    query = """
    SELECT column_name, data_type, data_length, nullable, data_default
    FROM dba_tab_columns 
    WHERE table_name = 'DBA_CONSTRAINTS' 
    ORDER BY column_id
    """
    
    try:
        cursor.execute(query)
        columns = cursor.fetchall()
        
        structure = []
        for col in columns:
            structure.append({
                'column_name': col[0],
                'data_type': col[1],
                'data_length': col[2],
                'nullable': col[3],
                'data_default': col[4]
            })
        
        return structure
    except Exception as e:
        print(f"获取字段结构失败: {e}")
        return []

def get_oracle_field_values(connection):
    """获取Oracle DBA_CONSTRAINTS的字段值分布"""
    cursor = connection.cursor()
    
    # 查询关键字段的值分布
    queries = {
        'constraint_type': "SELECT DISTINCT constraint_type FROM dba_constraints ORDER BY constraint_type",
        'status': "SELECT DISTINCT status FROM dba_constraints ORDER BY status",
        'deferrable': "SELECT DISTINCT deferrable FROM dba_constraints ORDER BY deferrable",
        'deferred': "SELECT DISTINCT deferred FROM dba_constraints ORDER BY deferred",
        'validated': "SELECT DISTINCT validated FROM dba_constraints ORDER BY validated",
        'generated': "SELECT DISTINCT generated FROM dba_constraints ORDER BY generated",
        'bad': "SELECT DISTINCT bad FROM dba_constraints ORDER BY bad",
        'rely': "SELECT DISTINCT rely FROM dba_constraints ORDER BY rely",
        'last_change': "SELECT DISTINCT last_change FROM dba_constraints ORDER BY last_change",
        'index_owner': "SELECT DISTINCT index_owner FROM dba_constraints WHERE index_owner IS NOT NULL ORDER BY index_owner",
        'index_name': "SELECT DISTINCT index_name FROM dba_constraints WHERE index_name IS NOT NULL ORDER BY index_name"
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
        owner, constraint_name, constraint_type, table_name, search_condition,
        r_owner, r_constraint_name, delete_rule, status, deferrable, deferred,
        validated, generated, bad, rely, last_change, index_owner, index_name,
        invalid, view_related, origin_con_id
    FROM dba_constraints 
    WHERE rownum <= 10
    ORDER BY owner, table_name, constraint_name
    """
    
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        
        sample_data = []
        for row in rows:
            sample_data.append({
                'owner': row[0],
                'constraint_name': row[1],
                'constraint_type': row[2],
                'table_name': row[3],
                'search_condition': row[4],
                'r_owner': row[5],
                'r_constraint_name': row[6],
                'delete_rule': row[7],
                'status': row[8],
                'deferrable': row[9],
                'deferred': row[10],
                'validated': row[11],
                'generated': row[12],
                'bad': row[13],
                'rely': row[14],
                'last_change': row[15],
                'index_owner': row[16],
                'index_name': row[17],
                'invalid': row[18],
                'view_related': row[19],
                'origin_con_id': row[20]
            })
        
        return sample_data
    except Exception as e:
        print(f"获取样本数据失败: {e}")
        return []

def get_constraint_type_stats(connection):
    """获取约束类型统计"""
    cursor = connection.cursor()
    
    query = """
    SELECT 
        constraint_type,
        COUNT(*) as count
    FROM dba_constraints
    GROUP BY constraint_type
    ORDER BY constraint_type
    """
    
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        
        stats = {}
        for row in rows:
            stats[row[0]] = row[1]
        
        return stats
    except Exception as e:
        print(f"获取约束类型统计失败: {e}")
        return {}

def main():
    """主函数"""
    print("开始分析Oracle DBA_CONSTRAINTS字段内容...")
    
    connection = connect_oracle()
    if not connection:
        return
    
    try:
        # 获取字段结构
        print("\n=== 字段结构 ===")
        structure = get_oracle_constraints_structure(connection)
        for col in structure:
            print(f"{col['column_name']}: {col['data_type']}({col['data_length']}) {'NULL' if col['nullable'] == 'Y' else 'NOT NULL'}")
        
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
        
        # 获取约束类型统计
        print("\n=== 约束类型统计 ===")
        constraint_stats = get_constraint_type_stats(connection)
        for constraint_type, count in constraint_stats.items():
            print(f"  {constraint_type}: {count}")
        
        # 保存结果到JSON文件
        result = {
            'timestamp': datetime.now().isoformat(),
            'structure': structure,
            'field_values': field_values,
            'sample_data': sample_data,
            'constraint_stats': constraint_stats
        }
        
        with open('oracle_constraints_analysis.json', 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        
        print("\n分析结果已保存到: oracle_constraints_analysis.json")
        
    except Exception as e:
        print(f"分析过程中出错: {e}")
    
    finally:
        connection.close()
        print("Oracle连接已关闭")

if __name__ == '__main__':
    main()











