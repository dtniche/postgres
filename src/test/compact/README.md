# Oracle兼容性视图验证工具

本目录包含用于验证PostgreSQL Oracle兼容性视图的工具和配置文件。

## 文件说明

- `oracle_compat_validation.py` - 主要的验证脚本
- `validation_config.yaml` - 配置文件，包含数据库连接参数和验证选项
- `validate_new_view.sh` - 自动化验证脚本，用于快速验证单个视图
- `test_workflow_example.md` - 详细的测试流程示例
- `README_testing.md` - 完整的测试指南
- `oracle_field_analysis.py` - Oracle字段内容分析工具，用于设计阶段的数据分析
- `requirements.txt` - Python依赖包列表
- `README.md` - 本说明文件
- `oracle_compat_views.md` - Oracle兼容视图设计文档

## 使用方法

### 1. 安装依赖

```bash
pip3 install -r requirements.txt
```

### 2. 创建配置文件（可选）

```bash
python3 oracle_compat_validation.py --create-config validation_config.yaml
```

### 3. 运行验证

#### 最简单的使用方式（推荐）
```bash
python3 oracle_compat_validation.py
```
- 自动使用 `validation_config.yaml` 配置文件（如果存在）
- 默认启用测试模式，显示PostgreSQL视图结构
- 默认启用详细输出

#### 新增视图测试流程（推荐）
```bash
# 使用自动化验证脚本
./validate_new_view.sh user_all_tables

# 查看详细测试流程
cat test_workflow_example.md

# 查看完整测试指南
cat README_testing.md
```

#### Oracle字段分析工具
```bash
# 运行Oracle字段内容分析（设计阶段使用）
python3 oracle_field_analysis.py

# 查看字段值分布
cat oracle_field_analysis.json | jq '.field_values'

# 查看样本数据
cat oracle_field_analysis.json | jq '.sample_data[0]'

# 查看NULL值统计
cat oracle_field_analysis.json | jq '.null_stats'
```

#### 指定配置文件
```bash
python3 oracle_compat_validation.py --config my_config.yaml
```

#### 验证特定视图
```bash
python3 oracle_compat_validation.py --views dba_tables all_tables
```

#### 完整验证模式（连接Oracle数据库）
```bash
python3 oracle_compat_validation.py --no-test-mode
```

#### 输出到文件
```bash
python3 oracle_compat_validation.py --output report.txt --json results.json
```

#### 详细输出
```bash
python3 oracle_compat_validation.py --verbose
```

### 4. 命令行参数

#### 主要参数
- `--config`, `-c` - 指定YAML配置文件路径
- `--create-config` - 创建默认配置文件
- `--views` - 指定要验证的视图名称列表
- `--no-test-mode` - 禁用测试模式，连接真实Oracle数据库
- `--verbose`, `-v` - 启用详细输出

#### 输出参数
- `--output`, `-o` - 指定报告输出文件路径
- `--json` - 指定JSON格式结果输出文件路径

#### 数据库连接参数（覆盖配置文件）
- `--pg-host` - PostgreSQL主机地址
- `--pg-port` - PostgreSQL端口
- `--pg-database` - PostgreSQL数据库名
- `--pg-user` - PostgreSQL用户名
- `--pg-password` - PostgreSQL密码
- `--oracle-host` - Oracle主机地址
- `--oracle-port` - Oracle端口
- `--oracle-service` - Oracle服务名
- `--oracle-user` - Oracle用户名
- `--oracle-password` - Oracle密码

### 5. 配置数据库连接

编辑 `validation_config.yaml` 文件：

```yaml
views:
  - dba_tables
  - all_tables
  - user_tables
  - dba_all_tables
  - all_all_tables
  - user_all_tables

postgresql:
  host: localhost
  port: 5432
  database: postgres
  user: postgres
  password: ''

oracle:
  host: localhost
  port: 1521
  service_name: XEPDB1
  user: sys
  password: '111111'

test_mode: false
verbose: true
output_file: validation_report.txt
json_file: validation_results.json
```

## 验证的视图

脚本会验证以下12个Oracle兼容视图：

### 表相关视图
1. `dba_tables` - 所有表（含系统表），86列
2. `all_tables` - 用户可见的所有表，86列
3. `user_tables` - 当前用户拥有的表，85列（不含owner）
4. `dba_all_tables` - DBA_ALL_TABLES兼容视图，70列
5. `all_all_tables` - ALL_ALL_TABLES兼容视图，70列
6. `user_all_tables` - USER_ALL_TABLES兼容视图，69列（不含owner）

### 函数参数相关视图
7. `dba_arguments` - 所有函数参数（含系统函数），29列
8. `all_arguments` - 用户可见的所有函数参数，29列
9. `user_arguments` - 当前用户拥有的函数参数，28列（不含owner）

### 列权限相关视图
10. `dba_col_privs` - 所有列权限（含系统对象），9列
11. `all_col_privs` - 用户可见的所有列权限，9列
12. `user_col_privs` - 当前用户拥有的列权限，9列（不含owner）

## 验证内容

- **列数量匹配** - 检查PostgreSQL和Oracle视图的列数是否一致
- **列名匹配** - 统一转换为小写比较列名
- **数据类型兼容性** - 验证数据类型映射是否正确
- **列位置顺序** - 检查列的顺序是否与Oracle一致
- **空值约束** - 验证NULL约束是否匹配

## 输出

验证结果会包含：

- **详细的列信息对比** - 显示每个列的PostgreSQL和Oracle类型
- **兼容性评分** - 0-100分的兼容性评分
- **差异报告** - 详细的差异列表和说明
- **类型映射错误信息** - 数据类型不匹配的详细信息
- **JSON格式结果** - 机器可读的验证结果

## 验证模式

脚本支持两种验证模式：

1. **测试模式**（默认）：只显示PostgreSQL视图结构，不连接Oracle数据库
   - 适用于开发阶段快速检查视图结构
   - 不需要Oracle数据库连接
   - 显示PostgreSQL视图的列信息

2. **完整验证模式**：连接Oracle数据库，比较PostgreSQL和Oracle视图的兼容性
   - 需要配置Oracle数据库连接
   - 提供完整的兼容性验证
   - 生成详细的对比报告

## 示例用法

### 快速检查PostgreSQL视图结构
```bash
python3 oracle_compat_validation.py --views dba_all_tables
```

### 完整验证所有视图
```bash
python3 oracle_compat_validation.py --no-test-mode --verbose
```

### 生成详细报告
```bash
python3 oracle_compat_validation.py --output detailed_report.txt --json results.json
```

### 使用自定义配置
```bash
python3 oracle_compat_validation.py --config my_config.yaml --views dba_tables all_tables
```

## 注意事项

- 确保PostgreSQL数据库已启动并可连接
- Oracle数据库连接需要安装 `cx_Oracle` 包
- 配置文件中的密码建议使用环境变量或安全存储
- 测试模式不需要Oracle数据库，适合开发环境使用
