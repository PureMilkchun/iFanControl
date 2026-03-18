#!/bin/bash

# MacFanControl 一键安装脚本

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "============================================"
echo "   MacFanControl 安装程序"
echo "============================================"
echo ""

# 检查文件
if [ ! -f "${SCRIPT_DIR}/kentsmc" ]; then
    echo -e "${RED}错误：找不到 kentsmc${NC}"
    exit 1
fi

if [ ! -d "${SCRIPT_DIR}/MacFanControl.app" ]; then
    echo -e "${RED}错误：找不到 MacFanControl.app${NC}"
    exit 1
fi

# 安装 kentsmc（只需要读取权限，不需要 sudo）
echo "步骤 1/2: 安装 kentsmc..."
sudo cp "${SCRIPT_DIR}/kentsmc" /usr/local/bin/kentsmc
sudo chmod 755 /usr/local/bin/kentsmc
echo -e "${GREEN}✓ kentsmc 已安装${NC}"

echo ""

# 安装 MacFanControl.app
echo "步骤 2/2: 安装 MacFanControl.app..."
if [ -d "/Applications/MacFanControl.app" ]; then
    rm -rf /Applications/MacFanControl.app
fi
cp -R "${SCRIPT_DIR}/MacFanControl.app" /Applications/
echo -e "${GREEN}✓ MacFanControl.app 已安装${NC}"

echo ""
echo "============================================"
echo -e "${GREEN}🎉 安装完成！${NC}"
echo "============================================"
echo ""
echo "现在可以运行 MacFanControl.app"
echo ""
echo "注意：首次运行时，应用会请求管理员权限"
echo "      请输入密码授权（仅此一次）"
echo ""
read -p "按回车键退出..."
