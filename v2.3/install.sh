#!/bin/bash

# iFanControl 一键安装脚本 v2.3
# 用户友好版本 - 支持双击运行

# ============================================
# 颜色定义
# ============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 状态追踪
# ============================================
KENTSMC_SUCCESS=false
SUDOERS_SUCCESS=false
APP_SUCCESS=false
SUDO_SUCCESS=false

# ============================================
# 获取脚本所在目录（关键：支持双击运行）
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# 如果 SCRIPT_DIR 为空或为根目录，尝试其他方法
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "/" ]; then
    # 可能是通过双击运行，尝试获取当前工作目录
    SCRIPT_DIR="$(pwd)"
fi

# ============================================
# 开始界面
# ============================================
clear 2>/dev/null || true
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║            🌬️  iFanControl v2.3 安装程序                  ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║       适用于 Apple Silicon Mac (M1/M2/M3/M4)              ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# 显示当前路径（帮助用户理解位置）
# ============================================
echo -e "${BLUE}📍 当前工作目录：${NC}"
echo -e "   ${CYAN}$SCRIPT_DIR${NC}"
echo ""

# ============================================
# 防呆提示
# ============================================
echo -e "${YELLOW}💡 提示：${NC}"
echo -e "   • 如果你是双击 Install.command 运行的，这是正确的 ✓"
echo -e "   • 输入密码时屏幕上不会显示任何字符，这是正常的 ✓"
echo -e "   • 直接输入密码后按回车即可"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================
# 步骤 0: 检查必要文件（路径容错）
# ============================================
echo -e "${YELLOW}[1/5]${NC} 检查安装文件..."

MISSING_FILES=()

if [ ! -f "${SCRIPT_DIR}/kentsmc" ]; then
    MISSING_FILES+=("kentsmc")
fi

if [ ! -d "${SCRIPT_DIR}/iFanControl.app" ]; then
    MISSING_FILES+=("iFanControl.app")
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo -e "${RED}✗ 错误：找不到以下文件：${NC}"
    for file in "${MISSING_FILES[@]}"; do
        echo -e "    - $file"
    done
    echo ""
    echo -e "${YELLOW}请确保你在解压后的文件夹内运行此脚本。${NC}"
    echo -e "${YELLOW}正确的做法：${NC}"
    echo -e "    1. 双击解压后的文件夹进入"
    echo -e "    2. 双击 Install.command 文件"
    echo ""
    echo -e "${CYAN}当前目录内容：${NC}"
    ls -la "$SCRIPT_DIR" 2>/dev/null | head -20
    echo ""
    read -p "按回车键退出..."
    exit 1
fi

echo -e "${GREEN}✓${NC} 所有安装文件就绪"
echo ""

# ============================================
# 步骤 1: 清除 quarantine 属性
# ============================================
echo -e "${YELLOW}[2/5]${NC} 清除隔离属性（防止"应用已损坏"）..."

# 清除当前目录下所有文件的 quarantine
find "$SCRIPT_DIR" -name "*.app" -o -name "kentsmc" 2>/dev/null | while read -r item; do
    xattr -cr "$item" 2>/dev/null || true
done
# 也清除目录本身
xattr -cr "$SCRIPT_DIR" 2>/dev/null || true

echo -e "${GREEN}✓${NC} 隔离属性已清除"
echo ""

# ============================================
# 步骤 2: 安装 kentsmc
# ============================================
echo -e "${YELLOW}[3/5]${NC} 安装 kentsmc 工具..."
echo -e "      ${CYAN}接下来会提示输入密码，请输入后按回车${NC}"
echo -e "      ${YELLOW}（输入时屏幕不会显示字符，这是正常的）${NC}"
echo ""

# 确保 /usr/local/bin 目录存在
if [ ! -d "/usr/local/bin" ]; then
    echo -e "  ${BLUE}→${NC} 创建 /usr/local/bin 目录..."
    sudo mkdir -p /usr/local/bin 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法创建 /usr/local/bin 目录${NC}"
        echo -e "${YELLOW}  请检查是否有管理员权限${NC}"
        exit 1
    fi
fi

# 复制 kentsmc
echo -e "  ${BLUE}→${NC} 复制 kentsmc 到 /usr/local/bin/..."
sudo cp "${SCRIPT_DIR}/kentsmc" /usr/local/bin/kentsmc
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 复制 kentsmc 失败${NC}"
    exit 1
fi

sudo chmod 755 /usr/local/bin/kentsmc
echo -e "${GREEN}✓${NC} kentsmc 安装成功"

# 验证
if [ -f "/usr/local/bin/kentsmc" ]; then
    KENTSMC_SUCCESS=true
else
    echo -e "${RED}✗ kentsmc 验证失败${NC}"
    exit 1
fi
echo ""

# ============================================
# 步骤 3: 配置 sudoers 免密授权
# ============================================
echo -e "${YELLOW}[4/5]${NC} 配置免密授权..."

# 确保 sudoers.d 目录存在
if [ ! -d "/private/etc/sudoers.d" ]; then
    echo -e "  ${BLUE}→${NC} 创建 /private/etc/sudoers.d 目录..."
    sudo mkdir -p /private/etc/sudoers.d 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法创建 sudoers.d 目录${NC}"
        echo -e "${YELLOW}  安装将继续，但每次使用可能需要输入密码${NC}"
    fi
fi

# 配置 sudoers
echo -e "  ${BLUE}→${NC} 写入免密配置..."
echo '%admin ALL=(ALL) NOPASSWD: /usr/local/bin/kentsmc' | sudo tee /private/etc/sudoers.d/kentsmc > /dev/null 2>&1
if [ $? -eq 0 ]; then
    sudo chmod 440 /private/etc/sudoers.d/kentsmc 2>/dev/null
    SUDOERS_SUCCESS=true
    echo -e "${GREEN}✓${NC} 免密配置完成"
else
    echo -e "${YELLOW}⚠${NC} 免密配置可能未生效（不影响使用，但每次可能需要输入密码）"
fi
echo ""

# ============================================
# 步骤 4: 安装应用
# ============================================
echo -e "${YELLOW}[5/5]${NC} 安装 iFanControl.app..."

# 如果已存在，先删除
if [ -d "/Applications/iFanControl.app" ]; then
    echo -e "  ${BLUE}→${NC} 移除旧版本..."
    rm -rf /Applications/iFanControl.app
fi

# 复制应用
echo -e "  ${BLUE}→${NC} 复制到 /Applications/..."
cp -R "${SCRIPT_DIR}/iFanControl.app" /Applications/
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 应用安装失败${NC}"
    exit 1
fi

# 清除隔离属性
sudo xattr -cr /Applications/iFanControl.app 2>/dev/null || true

# 验证
if [ -d "/Applications/iFanControl.app" ]; then
    APP_SUCCESS=true
    echo -e "${GREEN}✓${NC} 应用安装成功"
else
    echo -e "${RED}✗ 应用安装验证失败${NC}"
    exit 1
fi
echo ""

# ============================================
# 验证免密功能
# ============================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}🔍 验证安装结果...${NC}"
echo ""

# 测试免密执行
sudo -n /usr/local/bin/kentsmc -r Tp0e &>/dev/null
if [ $? -eq 0 ]; then
    SUDO_SUCCESS=true
    echo -e "${GREEN}✓${NC} 免密授权测试成功"
else
    echo -e "${YELLOW}⚠${NC} 免密授权可能需要重启后生效"
fi
echo ""

# ============================================
# 最终状态总结
# ============================================
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                      安装完成！🎉                          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}安装状态总结：${NC}"
echo ""

if [ "$KENTSMC_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} kentsmc 工具：已安装"
else
    echo -e "  ${RED}✗${NC} kentsmc 工具：未安装"
fi

if [ "$SUDOERS_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} 免密授权：已配置"
else
    echo -e "  ${YELLOW}⚠${NC} 免密授权：未完全配置"
fi

if [ "$APP_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} 应用程序：已安装到 /Applications/"
else
    echo -e "  ${RED}✗${NC} 应用程序：未安装"
fi

if [ "$SUDO_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} 功能测试：通过"
else
    echo -e "  ${YELLOW}⚠${NC} 功能测试：待重启后验证"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}下一步：${NC}"
echo ""
echo -e "  1. 打开 Finder → 进入「应用程序」文件夹"
echo -e "  2. 双击 ${CYAN}iFanControl.app${NC}"
echo -e "  3. 应用会出现在菜单栏，显示温度和风扇转速"
echo ""
echo -e "${YELLOW}注意：首次打开可能需要在「系统设置 → 隐私与安全性」中点击「仍要打开」${NC}"
echo ""
echo -e "${BLUE}如遇问题，可运行 ${CYAN}diagnose.sh${NC} 进行诊断${NC}"
echo ""
read -p "按回车键退出..."
