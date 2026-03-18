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

if [ ! -f "${SCRIPT_DIR}/kentsmc" ]; then
    echo -e "${RED}错误：找不到 kentsmc${NC}"
    exit 1
fi

if [ ! -d "${SCRIPT_DIR}/MacFanControl.app" ]; then
    echo -e "${RED}错误：找不到 MacFanControl.app${NC}"
    exit 1
fi

echo "正在安装组件..."
echo ""
echo "即将弹出密码对话框，请输入密码（仅需一次）"
echo ""

# 将 kentsmc 先复制到临时位置
cp "${SCRIPT_DIR}/kentsmc" /tmp/kentsmc_temp

# 一次完成：复制 kentsmc + 配置 sudoers
osascript -e "
do shell script \"
cp /tmp/kentsmc_temp /usr/local/bin/kentsmc
chmod 755 /usr/local/bin/kentsmc
rm -f /tmp/kentsmc_temp
echo '%admin ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc' > /private/etc/sudoers.d/kentsmc
chmod 440 /private/etc/sudoers.d/kentsmc
\" with administrator privileges
"

# 检查安装结果
if [ -f "/usr/local/bin/kentsmc" ]; then
    echo -e "${GREEN}✓ kentsmc 安装成功${NC}"
else
    echo -e "${RED}✗ kentsmc 安装失败${NC}"
    exit 1
fi

# 安装 MacFanControl.app
echo ""
echo "安装 MacFanControl.app..."
if [ -d "/Applications/MacFanControl.app" ]; then
    rm -rf /Applications/MacFanControl.app
fi
cp -R "${SCRIPT_DIR}/MacFanControl.app" /Applications/
echo -e "${GREEN}✓ MacFanControl.app 安装成功${NC}"

# 验证免密配置
echo ""
echo "验证免密授权..."
if sudo -n /usr/local/bin/kentsmc -r Tp0e &>/dev/null; then
    echo -e "${GREEN}✓ 免密授权配置成功${NC}"
else
    echo -e "${YELLOW}⚠ 免密授权可能需要重启${NC}"
fi

echo ""
echo "============================================"
echo -e "${GREEN}🎉 安装完成！${NC}"
echo "============================================"
echo ""
echo "现在可以直接运行 MacFanControl.app"
echo ""
read -p "按回车键退出..."
