#!/bin/bash

# MacFanControl 一键安装脚本
# 自动安装 kentsmc 并配置 sudoers 免密

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo ""
echo "============================================"
echo "   MacFanControl 安装程序"
echo "============================================"
echo ""

# 检查是否以 root 运行
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}请不要以 root 用户运行此脚本！${NC}"
    echo "请以普通用户身份运行，脚本会提示输入密码。"
    exit 1
fi

# 步骤 1: 安装 kentsmc
echo "步骤 1/3: 安装 kentsmc 工具..."
if [ -f "/usr/local/bin/kentsmc" ]; then
    echo -e "${YELLOW}kentsmc 已经安装，跳过${NC}"
else
    if [ ! -f "${SCRIPT_DIR}/kentsmc" ]; then
        echo -e "${RED}错误：找不到 kentsmc 安装文件${NC}"
        exit 1
    fi
    
    echo "安装 kentsmc 到 /usr/local/bin/kentsmc..."
    sudo cp "${SCRIPT_DIR}/kentsmc" /usr/local/bin/kentsmc
    sudo chown root:wheel /usr/local/bin/kentsmc
    sudo chmod 755 /usr/local/bin/kentsmc
    echo -e "${GREEN}✓ kentsmc 安装成功${NC}"
fi

echo ""

# 步骤 2: 安装 MacFanControl.app
echo "步骤 2/3: 安装 MacFanControl 应用..."
if [ ! -d "${SCRIPT_DIR}/MacFanControl.app" ]; then
    echo -e "${RED}错误：找不到 MacFanControl.app${NC}"
    exit 1
fi

if [ -d "/Applications/MacFanControl.app" ]; then
    echo -e "${YELLOW}MacFanControl.app 已经安装，将替换${NC}"
    rm -rf /Applications/MacFanControl.app
fi

cp -R "${SCRIPT_DIR}/MacFanControl.app" /Applications/
echo -e "${GREEN}✓ MacFanControl.app 安装成功${NC}"

echo ""

# 步骤 3: 配置 sudoers 免密
echo "步骤 3/3: 配置免密授权..."
echo "这将允许 MacFanControl 在不输入密码的情况下运行 kentsmc"
echo "请输入管理员密码："

# 检查 sudoers.d 是否支持
SUDOERS_SUPPORTED=true
if ! sudo grep -q "^#includedir /etc/sudoers.d" /etc/sudoers 2>/dev/null; then
    SUDOERS_SUPPORTED=false
fi

if [ "$SUDOERS_SUPPORTED" = true ]; then
    # 使用 sudoers.d（推荐方式）
    echo "kentsmc ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc" | sudo tee /etc/sudoers.d/kentsmc > /dev/null
    sudo chmod 440 /etc/sudoers.d/kentsmc
    
    # 验证配置
    if sudo -n /usr/local/bin/kentsmc --version &>/dev/null; then
        echo -e "${GREEN}✓ 免密授权配置成功${NC}"
    else
        echo -e "${YELLOW}⚠ 免密授权已配置，但验证失败${NC}"
        echo "  请手动检查 /etc/sudoers.d/kentsmc 文件"
    fi
else
    # 备用方案：提示用户手动配置
    echo -e "${YELLOW}⚠ 检测到系统不支持 sudoers.d 目录${NC}"
    echo ""
    echo "请手动运行以下命令配置免密："
    echo "  sudo visudo -f /etc/sudoers.d/kentsmc"
    echo ""
    echo "然后添加以下内容并保存："
    echo "  kentsmc ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc"
    echo ""
    echo "按回车键继续安装（稍后可手动配置）..."
    read
fi

echo ""
echo "============================================"
echo -e "${GREEN}🎉 安装完成！${NC}"
echo "============================================"
echo ""
echo "下一步："
echo "1. 打开「应用程序」文件夹"
echo "2. 双击运行 MacFanControl.app"
echo ""
echo "应用将在菜单栏显示温度和风扇转速。"
echo ""
echo "提示：应用启动后将直接运行，无需输入密码。"
echo ""
echo "按回车键退出..."
read
