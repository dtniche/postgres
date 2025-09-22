#!/usr/bin/env python3
"""
Oracle兼容性视图验证脚本

用于比较PostgreSQL和Oracle的兼容性视图，验证字段集合、名称与类型的一致性。
按照设计文档的目标：字段集合、名称与含义尽可能模拟Oracle；数值型统一NUMERIC，
时间使用TIMESTAMP（无时区），字符采用TEXT或name（当字段是PostgreSQL标识符时）。

作者: AI Assistant
版本: 1.0
"""

import argparse
import sys
import json
import logging
import os
import yaml
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from enum import Enum
import psycopg2
import cx_Oracle
from datetime import datetime

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('oracle_compat_validation.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class DatabaseType(Enum):
    POSTGRESQL = "postgresql"
    ORACLE = "oracle"

@dataclass
class DatabaseConfig:
    """数据库连接配置"""
    host: str = 'localhost'
    port: int = 5432
    database: str = 'postgres'
    user: str = 'postgres'
    password: str = ''
    service_name: Optional[str] = None

@dataclass
class ValidationConfig:
    """验证配置"""
    views: List[str]
    postgresql: DatabaseConfig
    oracle: Optional[DatabaseConfig] = None
    test_mode: bool = True  # 默认启用测试模式
    verbose: bool = True   # 默认启用详细输出
    output_file: Optional[str] = None
    json_file: Optional[str] = None


@dataclass
class ColumnInfo:
    """列信息数据类"""
    name: str
    data_type: str
    nullable: bool
    default_value: Optional[str] = None
    ordinal_position: int = 0
    character_maximum_length: Optional[int] = None
    numeric_precision: Optional[int] = None
    numeric_scale: Optional[int] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典，用于JSON序列化"""
        return asdict(self)

@dataclass
class ViewInfo:
    """视图信息数据类"""
    view_name: str
    columns: List[ColumnInfo]
    column_count: int
    database_type: DatabaseType
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典，用于JSON序列化"""
        return {
            'view_name': self.view_name,
            'columns': [col.to_dict() for col in self.columns],
            'column_count': self.column_count,
            'database_type': self.database_type.value
        }

class DatabaseConnector:
    """数据库连接器基类"""
    
    def __init__(self, connection_params: Dict[str, Any]):
        self.connection_params = connection_params
        self.connection = None
    
    def connect(self):
        """建立数据库连接"""
        raise NotImplementedError
    
    def disconnect(self):
        """断开数据库连接"""
        if self.connection:
            self.connection.close()
            self.connection = None
    
    def get_view_metadata(self, view_name: str) -> ViewInfo:
        """获取视图元数据"""
        raise NotImplementedError

class PostgreSQLConnector(DatabaseConnector):
    """PostgreSQL连接器"""
    
    def connect(self):
        """建立PostgreSQL连接"""
        try:
            self.connection = psycopg2.connect(**self.connection_params)
            logger.info("PostgreSQL连接成功")
        except Exception as e:
            logger.error(f"PostgreSQL连接失败: {e}")
            raise
    
    def get_view_metadata(self, view_name: str) -> ViewInfo:
        """获取PostgreSQL视图元数据"""
        if not self.connection:
            raise RuntimeError("数据库连接未建立")
        
        query = """
        SELECT 
            column_name,
            data_type,
            is_nullable,
            column_default,
            ordinal_position,
            character_maximum_length,
            numeric_precision,
            numeric_scale
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = %s
        ORDER BY ordinal_position;
        """
        
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query, (view_name,))
                rows = cursor.fetchall()
                
                if not rows:
                    raise ValueError(f"视图 '{view_name}' 不存在")
                
                columns = []
                for row in rows:
                    col = ColumnInfo(
                        name=row[0],
                        data_type=row[1],
                        nullable=row[2] == 'YES',
                        default_value=row[3],
                        ordinal_position=row[4],
                        character_maximum_length=row[5],
                        numeric_precision=row[6],
                        numeric_scale=row[7]
                    )
                    columns.append(col)
                
                return ViewInfo(
                    view_name=view_name,
                    columns=columns,
                    column_count=len(columns),
                    database_type=DatabaseType.POSTGRESQL
                )
                
        except Exception as e:
            logger.error(f"获取PostgreSQL视图元数据失败: {e}")
            raise

class OracleConnector(DatabaseConnector):
    """Oracle连接器"""
    
    def connect(self):
        """建立Oracle连接"""
        try:
            # 使用cx_Oracle连接Oracle
            dsn = cx_Oracle.makedsn(
                self.connection_params['host'],
                self.connection_params['port'],
                service_name=self.connection_params['service_name']
            )
            
            # 检查是否需要SYSDBA连接
            user = self.connection_params['user']
            if user.upper() == 'SYS':
                # SYS用户需要SYSDBA权限
                self.connection = cx_Oracle.connect(
                    self.connection_params['user'],
                    self.connection_params['password'],
                    dsn,
                    mode=cx_Oracle.SYSDBA
                )
                logger.info("Oracle连接成功 (SYSDBA模式)")
            else:
                self.connection = cx_Oracle.connect(
                    self.connection_params['user'],
                    self.connection_params['password'],
                    dsn
                )
                logger.info("Oracle连接成功")
        except Exception as e:
            logger.error(f"Oracle连接失败: {e}")
            raise
    
    def get_view_metadata(self, view_name: str) -> ViewInfo:
        """获取Oracle视图元数据"""
        if not self.connection:
            raise RuntimeError("数据库连接未建立")
        
        # 首先尝试从user_tab_columns获取（用户拥有的视图）
        query = """
        SELECT 
            column_name,
            data_type,
            nullable,
            data_default,
            column_id as ordinal_position,
            data_length as character_maximum_length,
            data_precision as numeric_precision,
            data_scale as numeric_scale
        FROM user_tab_columns 
        WHERE table_name = UPPER(:view_name)
        ORDER BY column_id
        """
        
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query, view_name=view_name.upper())
                rows = cursor.fetchall()
                
                # 如果user_tab_columns中没有找到，尝试从all_tab_columns获取
                if not rows:
                    query_all = """
                    SELECT 
                        column_name,
                        data_type,
                        nullable,
                        data_default,
                        column_id as ordinal_position,
                        data_length as character_maximum_length,
                        data_precision as numeric_precision,
                        data_scale as numeric_scale
                    FROM all_tab_columns 
                    WHERE table_name = UPPER(:view_name)
                    AND owner = USER
                    ORDER BY column_id
                    """
                    cursor.execute(query_all, view_name=view_name.upper())
                    rows = cursor.fetchall()
                
                # 如果还是没有找到，尝试从dba_tab_columns获取（需要DBA权限）
                if not rows:
                    query_dba = """
                    SELECT 
                        column_name,
                        data_type,
                        nullable,
                        data_default,
                        column_id as ordinal_position,
                        data_length as character_maximum_length,
                        data_precision as numeric_precision,
                        data_scale as numeric_scale
                    FROM dba_tab_columns 
                    WHERE table_name = UPPER(:view_name)
                    AND owner = USER
                    ORDER BY column_id
                    """
                    try:
                        cursor.execute(query_dba, view_name=view_name.upper())
                        rows = cursor.fetchall()
                    except Exception as dba_error:
                        logger.warning(f"无法从dba_tab_columns获取数据: {dba_error}")
                
                if not rows:
                    raise ValueError(f"视图 '{view_name}' 不存在或没有访问权限")
                
                columns = []
                for row in rows:
                    col = ColumnInfo(
                        name=row[0],
                        data_type=row[1],
                        nullable=row[2] == 'Y',
                        default_value=row[3],
                        ordinal_position=row[4],
                        character_maximum_length=row[5],
                        numeric_precision=row[6],
                        numeric_scale=row[7]
                    )
                    columns.append(col)
                
                return ViewInfo(
                    view_name=view_name,
                    columns=columns,
                    column_count=len(columns),
                    database_type=DatabaseType.ORACLE
                )
                
        except Exception as e:
            logger.error(f"获取Oracle视图元数据失败: {e}")
            raise

class ViewComparator:
    """视图比较器"""
    
    def __init__(self):
        self.differences = []
    
    def compare_views(self, pg_view: ViewInfo, oracle_view: ViewInfo) -> Dict[str, Any]:
        """比较两个视图的元数据"""
        logger.info(f"开始比较视图: {pg_view.view_name} vs {oracle_view.view_name}")
        
        # 打印详细的列信息
        print(f"\n{'='*80}")
        print(f"视图比较: {pg_view.view_name}")
        print(f"{'='*80}")
        
        print(f"\nPostgreSQL视图列信息 ({pg_view.column_count} 列):")
        print("-" * 60)
        for col in pg_view.columns:
            print(f"  {col.ordinal_position:2d}. {col.name:<30} {col.data_type:<15} {'NULL' if col.nullable else 'NOT NULL'}")
        
        print(f"\nOracle视图列信息 ({oracle_view.column_count} 列):")
        print("-" * 60)
        for col in oracle_view.columns:
            print(f"  {col.ordinal_position:2d}. {col.name:<30} {col.data_type:<15} {'NULL' if col.nullable else 'NOT NULL'}")
        
        comparison_result = {
            'view_name': pg_view.view_name,
            'postgresql': {
                'column_count': pg_view.column_count,
                'columns': {col.name: col for col in pg_view.columns}
            },
            'oracle': {
                'column_count': oracle_view.column_count,
                'columns': {col.name: col for col in oracle_view.columns}
            },
            'differences': [],
            'summary': {}
        }
        
        # 比较列数
        if pg_view.column_count != oracle_view.column_count:
            diff = {
                'type': 'column_count_mismatch',
                'postgresql_count': pg_view.column_count,
                'oracle_count': oracle_view.column_count,
                'message': f"列数不匹配: PostgreSQL({pg_view.column_count}) vs Oracle({oracle_view.column_count})"
            }
            comparison_result['differences'].append(diff)
            print(f"\n❌ 列数不匹配: PostgreSQL({pg_view.column_count}) vs Oracle({oracle_view.column_count})")
            logger.warning(diff['message'])
        
        # 比较列名和类型（统一转换为小写比较）
        pg_columns = set(col.name.lower() for col in pg_view.columns)
        oracle_columns = set(col.name.lower() for col in oracle_view.columns)
        
        # 检查缺失的列
        missing_in_oracle = pg_columns - oracle_columns
        missing_in_postgresql = oracle_columns - pg_columns
        
        if missing_in_oracle:
            print(f"\n❌ Oracle视图中缺失的列 ({len(missing_in_oracle)} 个):")
            for col_name in missing_in_oracle:
                diff = {
                    'type': 'missing_column',
                    'column_name': col_name,
                    'missing_in': 'oracle',
                    'message': f"Oracle视图中缺失列: {col_name}"
                }
                comparison_result['differences'].append(diff)
                print(f"  - {col_name}")
                logger.warning(diff['message'])
        
        if missing_in_postgresql:
            print(f"\n❌ PostgreSQL视图中缺失的列 ({len(missing_in_postgresql)} 个):")
            for col_name in missing_in_postgresql:
                diff = {
                    'type': 'missing_column',
                    'column_name': col_name,
                    'missing_in': 'postgresql',
                    'message': f"PostgreSQL视图中缺失列: {col_name}"
                }
                comparison_result['differences'].append(diff)
                print(f"  - {col_name}")
                logger.warning(diff['message'])
        
        # 比较共同列的类型和属性
        common_columns = pg_columns & oracle_columns
        type_mismatches = []
        position_mismatches = []
        
        if common_columns:
            print(f"\n📋 共同列详细比较 ({len(common_columns)} 个):")
            print("-" * 80)
            print(f"{'列名':<30} {'PostgreSQL类型':<15} {'Oracle类型':<15} {'兼容性':<10} {'位置差异':<10}")
            print("-" * 80)
        
        for col_name in common_columns:
            # 需要找到原始列名（因为比较时转换为了小写）
            pg_col = next(col for col in pg_view.columns if col.name.lower() == col_name)
            oracle_col = next(col for col in oracle_view.columns if col.name.lower() == col_name)
            
            # 比较数据类型
            is_type_compatible = self._is_compatible_type(pg_col.data_type, oracle_col.data_type)
            if not is_type_compatible:
                diff = {
                    'type': 'data_type_mismatch',
                    'column_name': col_name,
                    'postgresql_type': pg_col.data_type,
                    'oracle_type': oracle_col.data_type,
                    'message': f"列 {col_name} 数据类型不匹配: PostgreSQL({pg_col.data_type}) vs Oracle({oracle_col.data_type})"
                }
                comparison_result['differences'].append(diff)
                type_mismatches.append(col_name)
                logger.warning(diff['message'])
            
            # 比较列位置
            position_match = pg_col.ordinal_position == oracle_col.ordinal_position
            if not position_match:
                diff = {
                    'type': 'column_order_mismatch',
                    'column_name': col_name,
                    'postgresql_position': pg_col.ordinal_position,
                    'oracle_position': oracle_col.ordinal_position,
                    'message': f"列 {col_name} 位置不匹配: PostgreSQL({pg_col.ordinal_position}) vs Oracle({oracle_col.ordinal_position})"
                }
                comparison_result['differences'].append(diff)
                position_mismatches.append(col_name)
                logger.warning(diff['message'])
            
            # 打印详细比较信息
            if common_columns:
                compatibility = "✅ 兼容" if is_type_compatible else "❌ 不兼容"
                position_diff = f"PG:{pg_col.ordinal_position} vs OR:{oracle_col.ordinal_position}" if not position_match else "✅ 匹配"
                print(f"{col_name:<30} {pg_col.data_type:<15} {oracle_col.data_type:<15} {compatibility:<10} {position_diff:<10}")
        
        # 打印类型映射错误信息
        if type_mismatches:
            print(f"\n❌ 类型映射错误 ({len(type_mismatches)} 个):")
            for col_name in type_mismatches:
                pg_col = next(col for col in pg_view.columns if col.name.lower() == col_name)
                oracle_col = next(col for col in oracle_view.columns if col.name.lower() == col_name)
                print(f"  - {col_name}: PostgreSQL({pg_col.data_type}) → Oracle({oracle_col.data_type})")
                print(f"    映射规则: {self._get_type_mapping_rule(pg_col.data_type, oracle_col.data_type)}")
        
        # 打印位置不匹配信息
        if position_mismatches:
            print(f"\n⚠️  列位置不匹配 ({len(position_mismatches)} 个):")
            for col_name in position_mismatches:
                pg_col = next(col for col in pg_view.columns if col.name.lower() == col_name)
                oracle_col = next(col for col in oracle_view.columns if col.name.lower() == col_name)
                print(f"  - {col_name}: PostgreSQL位置{pg_col.ordinal_position} vs Oracle位置{oracle_col.ordinal_position}")
        
        # 生成摘要
        column_count_match = pg_view.column_count == oracle_view.column_count
        comparison_result['summary'] = {
            'total_differences': len(comparison_result['differences']),
            'column_count_match': column_count_match,
            'all_columns_present': len(missing_in_oracle) == 0 and len(missing_in_postgresql) == 0,
            'compatibility_score': self._calculate_compatibility_score(comparison_result, column_count_match)
        }
        
        return comparison_result
    
    def _is_compatible_type(self, pg_type: str, oracle_type: str) -> bool:
        """检查PostgreSQL和Oracle数据类型是否兼容"""
        # 根据设计文档的类型映射规则
        type_mapping = {
            'numeric': ['NUMBER', 'NUMERIC'],
            'text': ['VARCHAR2', 'CHAR', 'CLOB', 'TEXT'],
            'timestamp': ['DATE', 'TIMESTAMP'],
            'name': ['VARCHAR2', 'CHAR']  # 当字段是PostgreSQL标识符时
        }
        
        # 检查是否有匹配的映射
        for pg_base_type, oracle_types in type_mapping.items():
            if pg_type.startswith(pg_base_type):
                return any(oracle_type.startswith(ot) for ot in oracle_types)
        
        # 直接比较（大小写不敏感）
        return pg_type.upper() == oracle_type.upper()
    
    def _get_type_mapping_rule(self, pg_type: str, oracle_type: str) -> str:
        """获取类型映射规则说明"""
        type_mapping = {
            'numeric': 'PostgreSQL NUMERIC → Oracle NUMBER/NUMERIC',
            'text': 'PostgreSQL TEXT → Oracle VARCHAR2/CHAR/CLOB',
            'timestamp': 'PostgreSQL TIMESTAMP → Oracle DATE/TIMESTAMP',
            'name': 'PostgreSQL NAME → Oracle VARCHAR2/CHAR'
        }
        
        for pg_base_type, rule in type_mapping.items():
            if pg_type.startswith(pg_base_type):
                return rule
        
        return f"直接映射: {pg_type} → {oracle_type}"
    
    def _calculate_compatibility_score(self, comparison_result: Dict[str, Any], column_count_match: bool) -> float:
        """计算兼容性评分（0-100）"""
        total_columns = max(
            comparison_result['postgresql']['column_count'],
            comparison_result['oracle']['column_count']
        )
        
        if total_columns == 0:
            return 0.0
        
        # 基础分数：列数匹配
        base_score = 20 if column_count_match else 0
        
        # 列存在性分数
        missing_columns = len([d for d in comparison_result['differences'] if d['type'] == 'missing_column'])
        column_presence_score = max(0, 40 - (missing_columns * 2))
        
        # 类型兼容性分数
        type_mismatches = len([d for d in comparison_result['differences'] if d['type'] == 'data_type_mismatch'])
        type_compatibility_score = max(0, 40 - (type_mismatches * 3))
        
        return min(100.0, base_score + column_presence_score + type_compatibility_score)

def load_config(config_file: str) -> ValidationConfig:
    """从YAML配置文件加载配置"""
    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config_data = yaml.safe_load(f)
        
        # 解析PostgreSQL配置
        pg_config = DatabaseConfig(**config_data.get('postgresql', {}))
        
        # 解析Oracle配置（可选）
        oracle_config = None
        if 'oracle' in config_data and config_data['oracle']:
            oracle_config = DatabaseConfig(**config_data['oracle'])
        
        # 创建验证配置
        validation_config = ValidationConfig(
            views=config_data.get('views', []),
            postgresql=pg_config,
            oracle=oracle_config,
            test_mode=config_data.get('test_mode', False),
            verbose=config_data.get('verbose', False),
            output_file=config_data.get('output_file'),
            json_file=config_data.get('json_file')
        )
        
        logger.info(f"成功加载配置文件: {config_file}")
        return validation_config
        
    except Exception as e:
        logger.error(f"加载配置文件失败: {e}")
        raise

def merge_args_into_config(args: argparse.Namespace, config: ValidationConfig) -> ValidationConfig:
    """以YAML为主，命令行参数为辅的合并策略。
    - 仅当命令行提供对应参数时，才覆盖YAML中的值。
    - 特别规则：如果提供了 --views，则覆盖YAML中的视图列表。
    """
    # 覆盖视图列表
    if getattr(args, 'views', None):
        config.views = args.views

    # 覆盖开关类
    if getattr(args, 'no_test_mode', False):
        config.test_mode = False
    if getattr(args, 'verbose', False):
        config.verbose = True

    # 覆盖输出文件
    if getattr(args, 'output', None):
        config.output_file = args.output
    if getattr(args, 'json', None):
        config.json_file = args.json

    # 覆盖PG连接
    if getattr(args, 'pg_host', None):
        config.postgresql.host = args.pg_host
    if getattr(args, 'pg_port', None):
        config.postgresql.port = args.pg_port
    if getattr(args, 'pg_database', None):
        config.postgresql.database = args.pg_database
    if getattr(args, 'pg_user', None):
        config.postgresql.user = args.pg_user
    if getattr(args, 'pg_password', None) is not None:
        config.postgresql.password = args.pg_password

    # 覆盖Oracle连接
    oracle_cli_any = any(
        getattr(args, k, None) is not None for k in [
            'oracle_host', 'oracle_port', 'oracle_service', 'oracle_user', 'oracle_password'
        ]
    )
    if oracle_cli_any:
        if config.oracle is None:
            config.oracle = DatabaseConfig()
        if getattr(args, 'oracle_host', None):
            config.oracle.host = args.oracle_host
        if getattr(args, 'oracle_port', None):
            config.oracle.port = args.oracle_port
        if getattr(args, 'oracle_service', None):
            config.oracle.service_name = args.oracle_service
        if getattr(args, 'oracle_user', None):
            config.oracle.user = args.oracle_user
        if getattr(args, 'oracle_password', None) is not None:
            config.oracle.password = args.oracle_password

    return config

def serialize_results_for_json(results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """将结果转换为可JSON序列化的格式，包含PG与Oracle完整元数据。
    - 列以列表形式按 ordinal_position 排序保存，以保留顺序。
    """
    serialized_results = []
    
    for result in results:
        serialized_result = {
            'view_name': result['view_name'],
            'postgresql': {
                'column_count': result['postgresql']['column_count'],
                'columns': []
            },
            'oracle': {
                'column_count': result['oracle']['column_count'],
                'columns': []
            },
            'differences': result['differences'],
            'summary': result['summary']
        }
        
        # 转换PostgreSQL列信息（保持顺序）
        pg_cols: List[ColumnInfo] = list(result['postgresql']['columns'].values())
        pg_cols.sort(key=lambda c: c.ordinal_position)
        for col_info in pg_cols:
            serialized_result['postgresql']['columns'].append(col_info.to_dict() if hasattr(col_info, 'to_dict') else {
                'name': getattr(col_info, 'name', None),
                'data_type': getattr(col_info, 'data_type', None),
                'nullable': getattr(col_info, 'nullable', None),
                'default_value': getattr(col_info, 'default_value', None),
                'ordinal_position': getattr(col_info, 'ordinal_position', None),
                'character_maximum_length': getattr(col_info, 'character_maximum_length', None),
                'numeric_precision': getattr(col_info, 'numeric_precision', None),
                'numeric_scale': getattr(col_info, 'numeric_scale', None)
            })
        
        # 转换Oracle列信息（保持顺序）
        ora_cols: List[ColumnInfo] = list(result['oracle']['columns'].values())
        ora_cols.sort(key=lambda c: c.ordinal_position)
        for col_info in ora_cols:
            serialized_result['oracle']['columns'].append(col_info.to_dict() if hasattr(col_info, 'to_dict') else {
                'name': getattr(col_info, 'name', None),
                'data_type': getattr(col_info, 'data_type', None),
                'nullable': getattr(col_info, 'nullable', None),
                'default_value': getattr(col_info, 'default_value', None),
                'ordinal_position': getattr(col_info, 'ordinal_position', None),
                'character_maximum_length': getattr(col_info, 'character_maximum_length', None),
                'numeric_precision': getattr(col_info, 'numeric_precision', None),
                'numeric_scale': getattr(col_info, 'numeric_scale', None)
            })
        
        serialized_results.append(serialized_result)
    
    return serialized_results

def create_default_config(config_file: str):
    """创建默认配置文件"""
    default_config = {
        'views': [
            'dba_tables',
            'all_tables', 
            'user_tables',
            'dba_all_tables',
            'all_all_tables',
            'user_all_tables'
        ],
        'postgresql': {
            'host': 'localhost',
            'port': 5432,
            'database': 'postgres',
            'user': 'postgres',
            'password': ''
        },
        'oracle': {
            'host': 'localhost',
            'port': 1521,
            'service_name': 'XEPDB1',
            'user': 'sys',
            'password': '111111'
        },
        'test_mode': False,
        'verbose': True,
        'output_file': 'validation_report.txt',
        'json_file': 'validation_results.json'
    }
    
    try:
        with open(config_file, 'w', encoding='utf-8') as f:
            yaml.dump(default_config, f, default_flow_style=False, allow_unicode=True, indent=2)
        logger.info(f"默认配置文件已创建: {config_file}")
    except Exception as e:
        logger.error(f"创建默认配置文件失败: {e}")
        raise


class ValidationReport:
    """验证报告生成器"""
    
    def __init__(self):
        self.results = []
    
    def add_result(self, result: Dict[str, Any]):
        """添加比较结果"""
        self.results.append(result)
    
    def generate_report(self, output_file: Optional[str] = None) -> str:
        """生成验证报告"""
        report_lines = []
        report_lines.append("=" * 80)
        report_lines.append("Oracle兼容性视图验证报告")
        report_lines.append("=" * 80)
        report_lines.append(f"生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report_lines.append(f"验证视图数量: {len(self.results)}")
        report_lines.append("")
        
        # 总体统计
        total_differences = sum(r['summary']['total_differences'] for r in self.results)
        avg_compatibility = sum(r['summary']['compatibility_score'] for r in self.results) / len(self.results) if self.results else 0
        
        report_lines.append("总体统计:")
        report_lines.append(f"  总差异数: {total_differences}")
        report_lines.append(f"  平均兼容性评分: {avg_compatibility:.2f}/100")
        
        
        report_lines.append("")
        
        # 详细结果
        for i, result in enumerate(self.results, 1):
            report_lines.append(f"{i}. 视图: {result['view_name']}")
            report_lines.append(f"   PostgreSQL列数: {result['postgresql']['column_count']}")
            report_lines.append(f"   Oracle列数: {result['oracle']['column_count']}")
            report_lines.append(f"   兼容性评分: {result['summary']['compatibility_score']:.2f}/100")
            report_lines.append(f"   差异数量: {result['summary']['total_differences']}")
            
            if result['differences']:
                report_lines.append("   差异详情:")
                for diff in result['differences']:
                    report_lines.append(f"     - {diff['message']}")
            else:
                report_lines.append("   ✓ 无差异")
            
            report_lines.append("")
        
        report_content = "\n".join(report_lines)
        
        if output_file:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(report_content)
            logger.info(f"报告已保存到: {output_file}")
        
        return report_content

def main():
    """主函数"""
    print("Oracle兼容性视图验证脚本启动...")
    parser = argparse.ArgumentParser(description='Oracle兼容性视图验证脚本')
    parser.add_argument('--config', '-c', help='YAML配置文件路径（默认使用validation_config.yaml）')
    parser.add_argument('--create-config', help='创建默认配置文件')
    parser.add_argument('--views', nargs='+', help='要验证的视图名称列表（覆盖配置文件）')
    parser.add_argument('--no-test-mode', action='store_true', help='禁用测试模式，尝试连接真实Oracle数据库')
    parser.add_argument('--verbose', '-v', action='store_true', help='详细输出')
    
    # 兼容性参数（向后兼容）
    parser.add_argument('--pg-host', help='PostgreSQL主机地址')
    parser.add_argument('--pg-port', type=int, help='PostgreSQL端口')
    parser.add_argument('--pg-database', help='PostgreSQL数据库名')
    parser.add_argument('--pg-user', help='PostgreSQL用户名')
    parser.add_argument('--pg-password', help='PostgreSQL密码')
    parser.add_argument('--oracle-host', help='Oracle主机地址')
    parser.add_argument('--oracle-port', type=int, help='Oracle端口')
    parser.add_argument('--oracle-service', help='Oracle服务名')
    parser.add_argument('--oracle-user', help='Oracle用户名')
    parser.add_argument('--oracle-password', help='Oracle密码')
    parser.add_argument('--output', '-o', help='输出报告文件路径')
    parser.add_argument('--json', help='输出JSON格式结果到文件')
    
    args = parser.parse_args()
    
    # 如果指定了创建配置文件
    if args.create_config:
        create_default_config(args.create_config)
        return
    
    # 默认配置文件路径
    default_config_file = 'validation_config.yaml'
    
    # 加载配置
    config_file = args.config or default_config_file
    if os.path.exists(config_file):
        try:
            config = load_config(config_file)
            print(f"使用配置文件: {config_file}")
        except Exception as e:
            logger.error(f"无法加载配置文件 {config_file}: {e}")
            print(f"配置文件 {config_file} 加载失败，使用默认配置")
            config = None
    else:
        print(f"配置文件 {config_file} 不存在，使用默认配置")
        config = None
    
    if config is None:
        # 使用默认配置
        config = ValidationConfig(
            views=args.views or ['dba_tables', 'all_tables', 'user_tables', 'dba_all_tables', 'all_all_tables', 'user_all_tables'],
            postgresql=DatabaseConfig(
                host=args.pg_host or 'localhost',
                port=args.pg_port or 5432,
                database=args.pg_database or 'postgres',
                user=args.pg_user or 'postgres',
                password=args.pg_password or ''
            ),
            oracle=DatabaseConfig(
                host=args.oracle_host or 'localhost',
                port=args.oracle_port or 1521,
                service_name=args.oracle_service,
                user=args.oracle_user,
                password=args.oracle_password or ''
            ) if args.oracle_service and args.oracle_user and args.oracle_password else None,
            test_mode=not args.no_test_mode,  # 默认启用测试模式
            verbose=args.verbose,
            output_file=args.output,
            json_file=args.json
        )
    else:
        # 以YAML为主，用命令行提供的参数进行覆盖（仅在提供时）
        config = merge_args_into_config(args, config)
    
    if config.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # 验证必需参数
    if not config.postgresql.password:
        logger.warning("PostgreSQL密码未提供，将尝试无密码连接")
    
    # Oracle连接参数验证（可选，如果没有提供则跳过Oracle验证）
    oracle_available = config.oracle is not None
    if not oracle_available:
        logger.warning("Oracle连接参数不完整，将只验证PostgreSQL视图结构")
        logger.warning("如需完整验证，请在配置文件中提供Oracle连接信息")
    
    # 创建数据库连接器
    pg_connector = PostgreSQLConnector({
        'host': config.postgresql.host,
        'port': config.postgresql.port,
        'database': config.postgresql.database,
        'user': config.postgresql.user,
        'password': config.postgresql.password
    })
    
    oracle_connector = None
    if oracle_available:
        oracle_connector = OracleConnector({
            'host': config.oracle.host,
            'port': config.oracle.port,
            'service_name': config.oracle.service_name,
            'user': config.oracle.user,
            'password': config.oracle.password
        })
    
    # 创建比较器和报告生成器
    comparator = ViewComparator()
    report_generator = ValidationReport()
    
    try:
        # 建立数据库连接
        pg_connector.connect()
        if oracle_connector:
            oracle_connector.connect()
        
        # 验证每个视图
        for view_name in config.views:
            try:
                logger.info(f"开始验证视图: {view_name}")
                
                # 获取PostgreSQL视图元数据
                pg_view = pg_connector.get_view_metadata(view_name)
                logger.info(f"PostgreSQL视图 {view_name} 有 {pg_view.column_count} 列")
                
                if oracle_connector and not config.test_mode:
                    # 获取Oracle视图元数据
                    oracle_view = oracle_connector.get_view_metadata(view_name)
                    logger.info(f"Oracle视图 {view_name} 有 {oracle_view.column_count} 列")
                    
                    # 比较视图
                    comparison_result = comparator.compare_views(pg_view, oracle_view)
                    report_generator.add_result(comparison_result)
                    
                    logger.info(f"视图 {view_name} 验证完成，兼容性评分: {comparison_result['summary']['compatibility_score']:.2f}/100")
                else:
                    # 只显示PostgreSQL视图信息
                    print(f"\n{'='*80}")
                    print(f"PostgreSQL视图信息: {view_name}")
                    print(f"{'='*80}")
                    print(f"\nPostgreSQL视图列信息 ({pg_view.column_count} 列):")
                    print("-" * 60)
                    for col in pg_view.columns:
                        print(f"  {col.ordinal_position:2d}. {col.name:<30} {col.data_type:<15} {'NULL' if col.nullable else 'NOT NULL'}")
                    
                    # 创建模拟的比较结果
                    comparison_result = {
                        'view_name': view_name,
                        'postgresql': {
                            'column_count': pg_view.column_count,
                            'columns': {col.name: col for col in pg_view.columns}
                        },
                        'oracle': {
                            'column_count': 0,
                            'columns': {}
                        },
                        'differences': [{
                            'type': 'oracle_not_available',
                            'message': 'Oracle连接不可用，无法进行比较'
                        }],
                        'summary': {
                            'total_differences': 1,
                            'column_count_match': False,
                            'all_columns_present': False,
                            'compatibility_score': 0.0
                        }
                    }
                    report_generator.add_result(comparison_result)
                
            except Exception as e:
                logger.error(f"验证视图 {view_name} 时出错: {e}")
                continue
        
        
        # 生成报告
        report_content = report_generator.generate_report(config.output_file)
        print(report_content)
        
        # 输出JSON格式结果
        if config.json_file:
            json_results = {
                'timestamp': datetime.now().isoformat(),
                'views_validated': len(config.views),
                'results': serialize_results_for_json(report_generator.results)
            }
            with open(config.json_file, 'w', encoding='utf-8') as f:
                json.dump(json_results, f, indent=2, ensure_ascii=False)
            logger.info(f"JSON结果已保存到: {config.json_file}")
        
        
    except Exception as e:
        logger.error(f"验证过程中出错: {e}")
        sys.exit(1)
    
    finally:
        # 关闭数据库连接
        pg_connector.disconnect()
        if oracle_connector:
            oracle_connector.disconnect()

if __name__ == '__main__':
    main()
