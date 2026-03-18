#!/bin/bash

# MacFanControl 一键安装脚本 v2.0

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         MacFanControl v2.0 安装程序           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# 步骤 1: 清除 quarantine 属性
echo -e "${YELLOW}[1/4]${NC} 清除隔离属性..."

# 清除当前目录下所有文件的 quarantine
find "$SCRIPT_DIR" -name "*.app" -o -name "kentsmc" | while read -r item; do
    xattr -cr "$item" 2>/dev/null || true
done
# 也清除目录本身
xattr -cr "$SCRIPT_DIR" 2>/dev/null || true

echo -e "${GREEN}✓${NC} 隔离属性已清除"

# 检查必要文件
if [ ! -f "${SCRIPT_DIR}/kentsmc" ]; then
    echo -e "${RED}✗ 错误：找不到 kentsmc${NC}"
    exit 1
fi

if [ ! -d "${SCRIPT_DIR}/MacFanControl.app" ]; then
    echo -e "${RED}✗ 错误：找不到 MacFanControl.app${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[2/4]${NC} 安装 kentsmc 工具..."
echo -e "      ${BLUE}需要输入管理员密码（仅需这一次）${NC}"
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
    echo -e "${GREEN}✓${NC} kentsmc 已安装到 /usr/local/bin/"
else
    echo -e "${RED}✗ kentsmc 安装失败${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[3/4]${NC} 安装 MacFanControl.app..."

# 安装 MacFanControl.app
if [ -d "/Applications/MacFanControl.app" ]; then
    rm -rf /Applications/MacFanControl.app
fi
cp -R "${SCRIPT_DIR}/MacFanControl.app" /Applications/

# 再次清除 /Applications 下 app 的隔离属性，防止"应用已损坏"
sudo xattr -cr /Applications/MacFanControl.app 2>/dev/null || true

echo -e "${GREEN}✓${NC} 应用已安装到 /Applications/"

# 验证免密配置
echo ""
echo -e "${YELLOW}[4/4]${NC} 验证免密授权..."
if sudo -n /usr/local/bin/kentsmc -r Tp0e &>/dev/null; then
    echo -e "${GREEN}✓${NC} 免密授权配置成功"
else
    echo -e "${YELLOW}⚠${NC} 免密授权可能需要重启后生效"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                     安装完成！🎉                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}下一步：${NC}"
echo -e "  1. 打开 Finder，进入 /Applications/"
echo -e "  2. 双击 MacFanControl.app"
echo -e "  3. 应用会出现在菜单栏，显示温度和风扇转速"
echo ""
echo -e "  ${YELLOW}首次打开可能需要在「系统设置 → 隐私与安全性」中允许${NC}"
echo ""
read -p "按回车键退出..."
