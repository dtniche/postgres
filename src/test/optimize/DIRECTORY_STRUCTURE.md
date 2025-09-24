# 查询优化示例目录结构

## 目录说明

`src/test/optimize/` 目录包含了完整的数据库查询优化示例，支持 PostgreSQL 和 Oracle 两种数据库。

## 文件结构

```
src/test/optimize/
├── README.md                       # 使用说明文档
├── SQL_OPTIMIZATION_GUIDE.md       # 详细的优化指南文档
├── DIRECTORY_STRUCTURE.md          # 目录结构说明（本文件）
│
├── PostgreSQL 相关文件
├── sql_optimization_example.py     # PostgreSQL 完整的优化示例脚本
├── benchmark_test.py               # PostgreSQL 性能基准测试脚本
├── quick_optimization_test.sql     # PostgreSQL 快速 SQL 测试脚本
│
├── Oracle 相关文件
├── oracle_optimization_example.py # Oracle 数据库优化示例脚本
└── oracle_quick_test.sql           # Oracle 快速 SQL 测试脚本
```

## 文件说明

### 文档文件
- **README.md**: 项目使用说明，包含快速开始指南
- **SQL_OPTIMIZATION_GUIDE.md**: 详细的优化指南，包含理论知识和最佳实践
- **DIRECTORY_STRUCTURE.md**: 目录结构说明（本文件）

### PostgreSQL 相关文件
- **sql_optimization_example.py**: 完整的 PostgreSQL 优化示例脚本
  - 自动创建测试环境
  - 执行计划分析
  - 性能对比和优化建议
- **benchmark_test.py**: PostgreSQL 性能基准测试脚本
  - 测试不同数据规模下的优化效果
  - 生成详细的性能报告
- **quick_optimization_test.sql**: PostgreSQL 快速 SQL 测试脚本
  - 简单的 SQL 测试
  - 直接运行验证优化效果

### Oracle 相关文件
- **oracle_optimization_example.py**: Oracle 数据库优化示例脚本
  - 自动创建测试环境
  - Oracle 特定优化技巧演示
  - 使用提示和并行查询优化
- **oracle_quick_test.sql**: Oracle 快速 SQL 测试脚本
  - 简单的 SQL 测试
  - 包含执行计划分析

## 使用方法

### 快速开始
```bash
# 从项目根目录运行
cd /path/to/postgres

# PostgreSQL 快速测试
psql -d postgres -f src/test/optimize/quick_optimization_test.sql

# Oracle 快速测试
sqlplus sys/111111@172.23.160.1:1521/XEPDB1 as sysdba @src/test/optimize/oracle_quick_test.sql
```

### 完整示例
```bash
# PostgreSQL 完整示例
python3 src/test/optimize/sql_optimization_example.py

# Oracle 完整示例
python3 src/test/optimize/oracle_optimization_example.py

# PostgreSQL 基准测试
python3 src/test/optimize/benchmark_test.py
```

## 环境要求

### PostgreSQL 测试
- PostgreSQL 9.6+
- Python 3.6+
- 足够的数据库权限

### Oracle 测试
- Oracle 11g+ (推荐 19c+)
- Python 3.6+
- cx_Oracle 库
- 足够的数据库权限

## 注意事项

1. 所有脚本都会自动创建和清理测试环境
2. 确保有足够的数据库权限
3. 在生产环境中谨慎使用
4. 建议在测试环境中先验证效果

## 优化效果对比

| 数据库 | 性能提升 | 优化难度 | 适用场景 |
|--------|----------|----------|----------|
| PostgreSQL | 10-20倍 | 中等 | 所有复杂查询 |
| Oracle | 20-30% | 简单 | 大数据集查询 |
