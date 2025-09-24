#!/bin/bash
# validate_new_view.sh - 新视图验证脚本

VIEW_NAME=$1
if [ -z "$VIEW_NAME" ]; then
    echo "用法: $0 <view_name>"
    echo "示例: $0 user_all_tables"
    exit 1
fi

echo "=== 验证视图: $VIEW_NAME ==="

# 1. 运行兼容性验证
echo "1. 运行兼容性验证..."
python3 oracle_compat_validation.py --views $VIEW_NAME

# 2. 检查兼容性评分
echo "2. 检查兼容性评分..."
SCORE=$(python3 oracle_compat_validation.py --views $VIEW_NAME 2>/dev/null | grep "兼容性评分" | awk '{print $2}')
if [ -z "$SCORE" ]; then
    echo "无法获取兼容性评分，请检查验证工具是否正常运行"
    exit 1
fi
echo "兼容性评分: $SCORE"

# 3. 如果评分不是100%，显示差异
if [ "$SCORE" != "100%" ]; then
    echo "3. 显示差异详情..."
    python3 oracle_compat_validation.py --views $VIEW_NAME --output ${VIEW_NAME}_report.txt --json ${VIEW_NAME}_results.json
    echo "详细报告已保存到: ${VIEW_NAME}_report.txt"
    echo "JSON结果已保存到: ${VIEW_NAME}_results.json"
    
    # 显示主要差异
    echo ""
    echo "主要差异:"
    if [ -f "${VIEW_NAME}_report.txt" ]; then
        grep -A 5 "列数量" ${VIEW_NAME}_report.txt 2>/dev/null || echo "无列数量差异"
        grep -A 5 "列顺序" ${VIEW_NAME}_report.txt 2>/dev/null || echo "无列顺序差异"
        grep -A 5 "数据类型" ${VIEW_NAME}_report.txt 2>/dev/null || echo "无数据类型差异"
    fi
else
    echo "3. 兼容性验证通过！"
fi

# 4. 运行回归测试
echo "4. 运行回归测试..."
cd ../regress
if [ -f "pg_regress" ]; then
    ./pg_regress --schedule ora_schedule
    echo "回归测试完成"
else
    echo "警告: 未找到pg_regress，跳过回归测试"
fi

echo "=== 验证完成 ==="
