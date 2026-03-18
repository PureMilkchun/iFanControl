#!/bin/bash

# MacFanControl v3.0 一键安装脚本
# 使用 launchd 守护进程，彻底解决密码问题

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "============================================"
echo "   MacFanControl v3.0 安装程序"
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

if [ ! -f "${SCRIPT_DIR}/fancontrold.sh" ]; then
    echo -e "${RED}错误：找不到守护进程脚本${NC}"
    exit 1
fi

# 使用 AppleScript 一次性完成所有安装
echo "正在安装组件（需要管理员密码）..."
echo ""
echo "即将弹出密码对话框，请输入密码（仅需一次）"
echo ""

osascript -e "
do shell script \"
# 安装 kentsmc
cp '${SCRIPT_DIR}/kentsmc' /usr/local/bin/kentsmc
chmod 755 /usr/local/bin/kentsmc

# 安装守护进程脚本
cp '${SCRIPT_DIR}/fancontrold.sh' /usr/local/bin/fancontrold.sh
chmod 755 /usr/local/bin/fancontrold.sh

# 安装 launchd plist
cp '${SCRIPT_DIR}/com.macfancontrol.daemon.plist' /Library/LaunchDaemons/
chmod 644 /Library/LaunchDaemons/com.macfancontrol.daemon.plist

# 停止旧的守护进程（如果有）
launchctl unload /Library/LaunchDaemons/com.macfancontrol.daemon.plist 2>/dev/null || true

# 启动守护进程
launchctl load /Library/LaunchDaemons/com.macfancontrol.daemon.plist

echo 'done'
\" with administrator privileges
"

echo ""
echo -e "${GREEN}✓ 系统组件安装成功${NC}"

# 等待守护进程启动
sleep 1

# 安装 MacFanControl.app
echo ""
echo "安装 MacFanControl.app..."
if [ -d "/Applications/MacFanControl.app" ]; then
    rm -rf /Applications/MacFanControl.app
fi
cp -R "${SCRIPT_DIR}/MacFanControl.app" /Applications/
echo -e "${GREEN}✓ MacFanControl.app 安装成功${NC}"

# 验证守护进程
echo ""
echo "验证守护进程..."
if [ -p "/tmp/mfc_command" ]; then
    echo -e "${GREEN}✓ 守护进程运行中${NC}"
else
    echo -e "${YELLOW}⚠ 守护进程可能未启动，正在尝试启动...${NC}"
    sudo launchctl load /Library/LaunchDaemons/com.macfancontrol.daemon.plist 2>/dev/null || true
    sleep 1
    if [ -p "/tmp/mfc_command" ]; then
        echo -e "${GREEN}✓ 守护进程已启动${NC}"
    else
        echo -e "${YELLOW}⚠ 守护进程启动失败，请重启后重试${NC}"
    fi
fi

echo ""
echo "============================================"
echo -e "${GREEN}🎉 安装完成！${NC}"
echo "============================================"
echo ""
echo "现在可以直接运行 MacFanControl.app"
echo "运行时不会再弹出任何密码对话框！"
echo ""
echo "首次打开应用时，macOS 可能显示安全警告。"
echo "请在「系统设置 → 隐私与安全性」点击「仍要打开」"
echo ""
read -p "按回车键退出..."
