#!/bin/bash

# MacFanControl 安装测试脚本

echo "============================================"
echo "   MacFanControl 安装诊断"
echo "============================================"
echo ""

# 检查 kentsmc
echo "1. 检查 kentsmc..."
if [ -f "/usr/local/bin/kentsmc" ]; then
    echo "   ✓ kentsmc 已安装"
    ls -la /usr/local/bin/kentsmc
else
    echo "   ✗ kentsmc 未安装"
fi

echo ""

# 检查 sudoers 配置
echo "2. 检查 sudoers 配置..."
if [ -f "/etc/sudoers.d/kentsmc" ]; then
    echo "   ✓ sudoers.d/kentsmc 存在"
    cat /etc/sudoers.d/kentsmc
else
    echo "   ✗ sudoers.d/kentsmc 不存在"
fi

echo ""

# 检查 sudoers.d 支持
echo "3. 检查 sudoers.d 支持..."
if sudo cat /etc/sudoers 2>/dev/null | grep -q "#includedir /etc/sudoers.d"; then
    echo "   ✓ sudoers.d 已启用"
else
    echo "   ✗ sudoers.d 未启用"
fi

echo ""

# 测试 kentsmc 读取温度
echo "4. 测试读取温度（不需要 sudo）..."
/usr/local/bin/kentsmc -r Tp0e 2>/dev/null && echo "   ✓ 温度读取成功" || echo "   ✗ 温度读取失败"

echo ""

# 测试 sudo 免密
echo "5. 测试 sudo 免密执行..."
sudo -n /usr/local/bin/kentsmc -r Tp0e 2>/dev/null && echo "   ✓ sudo 免密成功" || echo "   ✗ sudo 免密失败"

echo ""
echo "============================================"
echo "诊断完成"
echo "============================================"
