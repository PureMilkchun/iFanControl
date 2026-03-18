#!/bin/bash

# MacFanControl 一键安装脚本

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 清除 quarantine 属性（可选，防止权限问题）
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true

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
echo "请输入管理员密码："
echo ""

# 将 kentsmc 先复制到临时位置
cp "${SCRIPT_DIR}/kentsmc" /tmp/kentsmc_temp

# 使用 sudo 直接执行（sudo 会缓存密码，后续命令无需再次输入）
sudo cp /tmp/kentsmc_temp /usr/local/bin/kentsmc
sudo chmod 755 /usr/local/bin/kentsmc
rm -f /tmp/kentsmc_temp

# 配置 sudoers 免密授权
echo '%admin ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc' | sudo tee /private/etc/sudoers.d/kentsmc > /dev/null
sudo chmod 440 /private/etc/sudoers.d/kentsmc

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

# 关键：清除复制后 app 的所有隔离属性，防止"应用已损坏"错误
sudo xattr -cr /Applications/MacFanControl.app 2>/dev/null || true
# 再次确认清除 quarantine
sudo xattr -d com.apple.quarantine /Applications/MacFanControl.app 2>/dev/null || true

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
