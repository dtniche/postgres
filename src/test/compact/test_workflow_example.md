# 新增视图测试流程示例

## 示例：验证 user_all_tables 视图

### 1. 运行兼容性验证

```bash
# 验证单个视图
python3 oracle_compat_validation.py --views user_all_tables

# 验证多个视图
python3 oracle_compat_validation.py --views dba_all_tables all_all_tables user_all_tables

# 生成详细报告
python3 oracle_compat_validation.py --views user_all_tables --output detailed_report.txt --json results.json
```

### 2. 分析验证结果

```bash
# 查看Oracle列结构
python3 -c "
import json
with open('validation_results.json', 'r') as f:
    data = json.load(f)
for result in data['results']:
    if result['view_name'] == 'user_all_tables':
        print('Oracle列结构:')
        for col in result['oracle']['columns']:
            print(f'{col[\"ordinal_position\"]:2d}. {col[\"name\"]:<30} {col[\"data_type\"]:<15}')
        break
"

# 查看PostgreSQL列结构
psql -d postgres -c "SELECT column_name, ordinal_position, data_type FROM information_schema.columns WHERE table_name = 'user_all_tables' ORDER BY ordinal_position;"
```

### 3. 对比分析结果

```bash
# 查看兼容性评分
grep "兼容性评分" validation_report.txt

# 查看列数量对比
grep "列数量" validation_report.txt

# 查看列顺序差异
grep -A 5 "列顺序" validation_report.txt

# 查看数据类型差异
grep -A 10 "数据类型" validation_report.txt
```

### 4. 修正实现

```bash
# 1. 编辑视图定义文件
vim src/backend/catalog/oracle_compat_views.sql

# 2. 根据Oracle列结构调整PostgreSQL实现
# - 调整RETURNS TABLE中的列顺序
# - 修正数据类型映射
# - 确保列名完全匹配

# 3. 重新创建视图
psql -d postgres -f src/backend/catalog/oracle_compat_views.sql

# 4. 重新验证
python3 oracle_compat_validation.py --views user_all_tables
```

### 5. 验证修正结果

```bash
# 检查最终兼容性评分
python3 oracle_compat_validation.py --views user_all_tables | grep "兼容性评分"

# 查看详细差异（应该为空或很少）
python3 oracle_compat_validation.py --views user_all_tables --output final_report.txt
grep -A 10 "差异详情" final_report.txt

# 运行回归测试
cd ../regress
./pg_regress --schedule ora_schedule
```

### 6. 测试流程检查清单

- [ ] 新视图已添加到 `validation_config.yaml`
- [ ] 运行 `python3 oracle_compat_validation.py --views new_view` 验证元数据
- [ ] 检查列数量是否匹配Oracle
- [ ] 检查列顺序是否与Oracle一致
- [ ] 检查数据类型映射是否正确
- [ ] 检查列名是否完全匹配（大小写不敏感）
- [ ] 兼容性评分达到100%
- [ ] 运行回归测试通过
- [ ] 更新设计文档和README

## 常见问题解决

### 问题1：列顺序不匹配
```bash
# 查看Oracle列顺序
python3 -c "
import json
with open('validation_results.json', 'r') as f:
    data = json.load(f)
for result in data['results']:
    if result['view_name'] == 'user_all_tables':
        oracle_cols = [col['name'] for col in result['oracle']['columns']]
        print('Oracle列顺序:', oracle_cols)
        break
"

# 查看PostgreSQL列顺序
psql -d postgres -c "SELECT column_name FROM information_schema.columns WHERE table_name = 'user_all_tables' ORDER BY ordinal_position;"
```

### 问题2：数据类型不匹配
```bash
# 查看数据类型差异
python3 -c "
import json
with open('validation_results.json', 'r') as f:
    data = json.load(f)
for result in data['results']:
    if result['view_name'] == 'user_all_tables':
        print('数据类型对比:')
        for col in result['oracle']['columns']:
            pg_col = next((c for c in result['postgresql']['columns'] if c['name'].lower() == col['name'].lower()), None)
            if pg_col and col['data_type'] != pg_col['data_type']:
                print(f'{col[\"name\"]}: Oracle({col[\"data_type\"]}) vs PostgreSQL({pg_col[\"data_type\"]})')
        break
"
```

### 问题3：列名不匹配
```bash
# 查看列名差异
python3 -c "
import json
with open('validation_results.json', 'r') as f:
    data = json.load(f)
for result in data['results']:
    if result['view_name'] == 'user_all_tables':
        oracle_names = {col['name'].lower(): col['name'] for col in result['oracle']['columns']}
        pg_names = {col['name'].lower(): col['name'] for col in result['postgresql']['columns']}
        print('列名差异:')
        for name in set(oracle_names.keys()) | set(pg_names.keys()):
            if name not in oracle_names:
                print(f'PostgreSQL独有: {pg_names[name]}')
            elif name not in pg_names:
                print(f'Oracle独有: {oracle_names[name]}')
            elif oracle_names[name] != pg_names[name]:
                print(f'大小写不同: Oracle({oracle_names[name]}) vs PostgreSQL({pg_names[name]})')
        break
"
```

## 自动化验证脚本

```bash
#!/bin/bash
# validate_new_view.sh - 新视图验证脚本

VIEW_NAME=$1
if [ -z "$VIEW_NAME" ]; then
    echo "用法: $0 <view_name>"
    exit 1
fi

echo "=== 验证视图: $VIEW_NAME ==="

# 1. 运行兼容性验证
echo "1. 运行兼容性验证..."
python3 oracle_compat_validation.py --views $VIEW_NAME

# 2. 检查兼容性评分
echo "2. 检查兼容性评分..."
SCORE=$(python3 oracle_compat_validation.py --views $VIEW_NAME | grep "兼容性评分" | awk '{print $2}')
echo "兼容性评分: $SCORE"

# 3. 如果评分不是100%，显示差异
if [ "$SCORE" != "100%" ]; then
    echo "3. 显示差异详情..."
    python3 oracle_compat_validation.py --views $VIEW_NAME --output ${VIEW_NAME}_report.txt
    echo "详细报告已保存到: ${VIEW_NAME}_report.txt"
else
    echo "3. 兼容性验证通过！"
fi

# 4. 运行回归测试
echo "4. 运行回归测试..."
cd ../regress
./pg_regress --schedule ora_schedule
echo "回归测试完成"
```

使用方法：
```bash
chmod +x validate_new_view.sh
./validate_new_view.sh user_all_tables
```

