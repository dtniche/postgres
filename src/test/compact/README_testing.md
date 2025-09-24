# Oracle兼容性视图测试指南

## 概述

本文档提供了完整的Oracle兼容性视图测试流程，包括新增视图的验证方法和工具使用指南。

## 快速开始

### 1. 验证现有视图

```bash
# 验证所有视图
python3 oracle_compat_validation.py

# 验证特定视图
python3 oracle_compat_validation.py --views user_all_tables

# 使用自动化脚本
./validate_new_view.sh user_all_tables
```

### 2. 新增视图测试流程

#### 步骤1：更新配置文件
```bash
# 编辑配置文件
vim validation_config.yaml

# 添加新视图到验证列表
views:
  - dba_new_view
  - all_new_view  
  - user_new_view
```

#### 步骤2：运行兼容性验证
```bash
# 验证新视图
python3 oracle_compat_validation.py --views dba_new_view all_new_view user_new_view

# 生成详细报告
python3 oracle_compat_validation.py --views dba_new_view --output detailed_report.txt --json results.json
```

#### 步骤3：分析验证结果
```bash
# 查看Oracle列结构
python3 -c "
import json
with open('validation_results.json', 'r') as f:
    data = json.load(f)
for result in data['results']:
    if result['view_name'] == 'dba_new_view':
        print('Oracle列结构:')
        for col in result['oracle']['columns']:
            print(f'{col[\"ordinal_position\"]:2d}. {col[\"name\"]:<30} {col[\"data_type\"]:<15}')
        break
"

# 对比PostgreSQL列结构
psql -d postgres -c "SELECT column_name, ordinal_position, data_type FROM information_schema.columns WHERE table_name = 'dba_new_view' ORDER BY ordinal_position;"
```

#### 步骤4：修正实现
```bash
# 1. 编辑视图定义
vim src/backend/catalog/oracle_compat_views.sql

# 2. 重新创建视图
psql -d postgres -f src/backend/catalog/oracle_compat_views.sql

# 3. 重新验证
python3 oracle_compat_validation.py --views dba_new_view
```

#### 步骤5：运行回归测试
```bash
cd ../regress
./pg_regress --schedule ora_schedule
```

## 验证工具说明

### 1. 兼容性验证脚本 (oracle_compat_validation.py)

**功能**：
- 比较PostgreSQL和Oracle视图的元数据
- 检查列数量、列名、数据类型、列顺序
- 生成兼容性评分和详细报告

**使用方法**：
```bash
# 基本用法
python3 oracle_compat_validation.py

# 指定视图
python3 oracle_compat_validation.py --views view1 view2

# 生成报告
python3 oracle_compat_validation.py --output report.txt --json results.json

# 指定配置文件
python3 oracle_compat_validation.py --config custom_config.yaml
```

### 2. 自动化验证脚本 (validate_new_view.sh)

**功能**：
- 一键验证单个视图
- 自动检查兼容性评分
- 生成详细报告
- 运行回归测试

**使用方法**：
```bash
# 验证单个视图
./validate_new_view.sh user_all_tables

# 查看帮助
./validate_new_view.sh
```

## 验证结果解读

### 兼容性评分

- **100%**: 完全兼容，无需修改
- **90-99%**: 基本兼容，可能有轻微差异
- **80-89%**: 需要调整，存在明显差异
- **<80%**: 需要重大修改

### 常见差异类型

1. **列数量不匹配**
   - PostgreSQL和Oracle的列数不同
   - 需要检查视图定义是否完整

2. **列顺序不匹配**
   - 列的顺序与Oracle不一致
   - 需要调整RETURNS TABLE中的列顺序

3. **数据类型不匹配**
   - PostgreSQL和Oracle的数据类型映射不正确
   - 需要修正数据类型转换

4. **列名不匹配**
   - 列名与Oracle不完全一致
   - 需要确保列名完全匹配（大小写不敏感）

## 测试检查清单

### 新增视图验证清单

- [ ] 视图已添加到 `validation_config.yaml`
- [ ] 运行兼容性验证脚本
- [ ] 检查列数量是否匹配Oracle
- [ ] 检查列顺序是否与Oracle一致
- [ ] 检查数据类型映射是否正确
- [ ] 检查列名是否完全匹配
- [ ] 兼容性评分达到100%
- [ ] 运行回归测试通过
- [ ] 更新设计文档和README

### 回归测试清单

- [ ] 更新 `src/test/regress/sql/oracle_compat_views.sql`
- [ ] 添加新视图的测试用例
- [ ] 测试列数量、列名、数据类型
- [ ] 测试权限模型
- [ ] 运行 `./pg_regress --schedule ora_schedule`
- [ ] 检查测试结果，修正差异

## 故障排除

### 问题1：连接失败

```bash
# 检查PostgreSQL连接
psql -d postgres -c "SELECT version();"

# 检查Oracle连接
sqlplus / as sysdba
```

### 问题2：视图不存在

```bash
# 检查PostgreSQL视图
psql -d postgres -c "\dv *view_name*"

# 检查Oracle视图
sqlplus / as sysdba
SELECT * FROM user_views WHERE view_name = 'VIEW_NAME';
```

### 问题3：权限问题

```bash
# 检查PostgreSQL权限
psql -d postgres -c "\dp *view_name*"

# 检查Oracle权限
sqlplus / as sysdba
SELECT * FROM dba_tab_privs WHERE table_name = 'VIEW_NAME';
```

## 相关文件

- `oracle_compat_validation.py`: 兼容性验证脚本
- `validate_new_view.sh`: 自动化验证脚本
- `validation_config.yaml`: 验证配置文件
- `test_workflow_example.md`: 详细测试流程示例
- `oracle_compat_views.md`: 设计文档
- `README.md`: 项目说明文档

## 最佳实践

1. **先验证后实现**: 在实现新视图前，先了解Oracle的列结构
2. **逐步验证**: 每次修改后立即验证，避免累积问题
3. **详细记录**: 记录每次验证的结果和修改内容
4. **自动化测试**: 使用自动化脚本提高效率
5. **持续集成**: 将验证流程集成到CI/CD中

## 联系支持

如有问题，请参考：
- 设计文档：`oracle_compat_views.md`
- 测试示例：`test_workflow_example.md`
- 项目说明：`README.md`

