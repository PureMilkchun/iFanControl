#!/bin/bash

# MacFanControl v3.0 卸载脚本

echo "============================================"
echo "   MacFanControl 卸载程序"
echo "============================================"
echo ""

# 停止并卸载守护进程
echo "步骤 1/4: 停止守护进程..."
sudo launchctl unload /Library/LaunchDaemons/com.macfancontrol.daemon.plist 2>/dev/null || true
echo "✓ 守护进程已停止"

# 删除守护进程文件
echo ""
echo "步骤 2/4: 删除守护进程..."
sudo rm -f /usr/local/bin/fancontrold.sh
sudo rm -f /Library/LaunchDaemons/com.macfancontrol.daemon.plist
rm -f /tmp/mfc_command /tmp/mfc_result /tmp/mfc.lock /tmp/mfc_daemon.log
echo "✓ 守护进程已删除"

# 删除 kentsmc
echo ""
echo "步骤 3/4: 删除 kentsmc..."
sudo rm -f /usr/local/bin/kentsmc
echo "✓ kentsmc 已删除"

# 删除 MacFanControl.app
echo ""
echo "步骤 4/4: 删除 MacFanControl.app..."
rm -rf /Applications/MacFanControl.app
rm -rf ~/Library/Application\ Support/MacFanControl
echo "✓ MacFanControl.app 已删除"

echo ""
echo "============================================"
echo "   卸载完成！"
echo "============================================"
echo ""
read -p "按回车键退出..."
