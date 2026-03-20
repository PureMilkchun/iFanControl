#!/bin/bash

# iFanControl 卸载脚本

echo "============================================"
echo "   iFanControl 卸载程序"
echo "============================================"
echo ""

if [ "$EUID" -eq 0 ]; then 
    echo "请不要以 root 用户运行此脚本！"
    exit 1
fi

# 步骤 1: 删除 kentsmc
echo "步骤 1/4: 删除 kentsmc..."
if [ -f "/usr/local/bin/kentsmc" ]; then
    sudo rm -f /usr/local/bin/kentsmc
    echo "✓ kentsmc 已删除"
else
    echo "kentsmc 未安装，跳过"
fi

# 步骤 2: 删除 sudoers 配置
echo ""
echo "步骤 2/4: 删除免密配置..."
if [ -f "/etc/sudoers.d/kentsmc" ]; then
    sudo rm -f /etc/sudoers.d/kentsmc
    echo "✓ sudoers 配置已删除"
else
    echo "sudoers 配置不存在，跳过"
fi

# 步骤 3: 删除 iFanControl.app
echo ""
echo "步骤 3/4: 删除 iFanControl.app..."
if [ -d "/Applications/iFanControl.app" ]; then
    rm -rf /Applications/iFanControl.app
    echo "✓ iFanControl.app 已删除"
else
    echo "iFanControl.app 未安装，跳过"
fi

# 步骤 4: 删除配置文件
echo ""
echo "步骤 4/4: 删除配置文件..."
if [ -d "$HOME/Library/Application Support/iFanControl" ]; then
    rm -rf "$HOME/Library/Application Support/iFanControl"
    echo "✓ 配置文件已删除"
else
    echo "配置文件不存在，跳过"
fi

echo ""
echo "============================================"
echo "   卸载完成！"
echo "============================================"
echo ""
echo "按回车键退出..."
read
