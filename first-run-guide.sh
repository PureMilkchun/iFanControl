#!/bin/bash

# MacFanControl 首次运行引导脚本
# 帮助用户绕过 Gatekeeper 安全检查

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "============================================"
echo "   MacFanControl 首次运行引导"
echo "============================================"
echo ""
echo "由于应用未经过 Apple 签名，首次运行时"
echo "macOS 可能会显示安全警告。"
echo ""
echo "请按以下步骤操作："
echo ""
echo -e "${YELLOW}步骤 1:${NC} 双击打开 MacFanControl.app"
echo "        （会显示安全警告）"
echo ""
echo -e "${YELLOW}步骤 2:${NC} 打开「系统设置」"
echo "        点击 Dock 栏中的齿轮图标，或点击屏幕"
echo "        右上角的苹果菜单 → 系统设置"
echo ""
echo -e "${YELLOW}步骤 3:${NC} 进入「隐私与安全性」"
echo "        在左侧栏找到「隐私与安全性」"
echo ""
echo -e "${YELLOW}步骤 4:${NC} 找到安全性区域"
echo "        向下滚动到「安全性」部分"
echo ""
echo -e "${YELLOW}步骤 5:${NC} 点击「仍要打开」"
echo "        会显示「MacFanControl.app 已被阻止」"
echo "        点击旁边的「仍要打开」按钮"
echo ""
echo -e "${YELLOW}步骤 6:${NC} 确认打开"
echo "        在弹出的对话框中点击「打开」"
echo ""
echo "完成以上步骤后，以后双击即可正常运行。"
echo ""
echo "============================================"
echo ""
read -p "按回车键打开系统设置的隐私与安全性页面..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Security"
