#!/bin/bash

# iFanControl 一键安装脚本 v2.9.5
# 用户友好版本 - 拖拽安装

# ============================================
# 颜色定义
# ============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================
# 状态追踪
# ============================================
KENTSMC_SUCCESS=false
SUDOERS_SUCCESS=false
APP_SUCCESS=false
SUDO_SUCCESS=false

# ============================================
# 获取脚本所在目录
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "/" ]; then
    SCRIPT_DIR="$(pwd)"
fi

# ============================================
# 开始界面
# ============================================
clear 2>/dev/null || true
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║          🌬️  iFanControl v2.9.5 安装程序                 ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║   适用于带风扇的 Apple Silicon Mac (M1/M2/M3/M4/M5)    ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# 显示当前路径
# ============================================
echo -e "${BLUE}📍 当前工作目录：${NC}"
echo -e "   ${CYAN}$SCRIPT_DIR${NC}"
echo ""

# ============================================
# 防呆提示
# ============================================
echo -e "${YELLOW}💡 提示：${NC}"
echo -e "   • 如果你是将 install.sh 拖入终端运行的，这是正确的 ✓"
echo -e "   • 输入密码时屏幕上不会显示任何字符，这是正常的 ✓"
echo -e "   • 直接输入密码后按回车即可"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================
# 步骤 0: 检查必要文件
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
    echo -e "    1. 打开终端"
    echo -e "    2. 将 install.sh 拖入终端"
    echo -e "    3. 按回车执行"
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

find "$SCRIPT_DIR" -name "*.app" -o -name "kentsmc" 2>/dev/null | while read -r item; do
    xattr -cr "$item" 2>/dev/null || true
done
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

if [ ! -d "/usr/local/bin" ]; then
    echo -e "  ${BLUE}→${NC} 创建 /usr/local/bin 目录..."
    sudo mkdir -p /usr/local/bin 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法创建 /usr/local/bin 目录${NC}"
        echo -e "${YELLOW}  请检查是否有管理员权限${NC}"
        exit 1
    fi
fi

echo -e "  ${BLUE}→${NC} 复制 kentsmc 到 /usr/local/bin/..."
sudo cp "${SCRIPT_DIR}/kentsmc" /usr/local/bin/kentsmc
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 复制 kentsmc 失败${NC}"
    exit 1
fi

sudo chmod 755 /usr/local/bin/kentsmc
echo -e "${GREEN}✓${NC} kentsmc 安装成功"

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

if [ ! -d "/private/etc/sudoers.d" ]; then
    echo -e "  ${BLUE}→${NC} 创建 /private/etc/sudoers.d 目录..."
    sudo mkdir -p /private/etc/sudoers.d 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 无法创建 sudoers.d 目录${NC}"
        echo -e "${YELLOW}  安装将继续，但每次使用可能需要输入密码${NC}"
    fi
fi

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

WAS_RUNNING=false
if pgrep -f "/Applications/iFanControl.app/Contents/MacOS/iFanControl" >/dev/null 2>&1; then
    WAS_RUNNING=true
    echo -e "  ${BLUE}→${NC} 检测到 iFanControl 正在运行，准备自动重启..."
    osascript -e 'tell application id "com.ifancontrol.app" to quit' >/dev/null 2>&1 || true
    pkill -f "/Applications/iFanControl.app/Contents/MacOS/iFanControl" >/dev/null 2>&1 || true
    sleep 1
fi

if [ -d "/Applications/iFanControl.app" ]; then
    echo -e "  ${BLUE}→${NC} 移除旧版本..."
    rm -rf /Applications/iFanControl.app
fi

# 清理历史残留的备份文件
for old in /Applications/iFanControl.app.backup-* /Applications/iFanControl.app.malformed-*; do
    if [ -e "$old" ]; then
        echo -e "  ${BLUE}→${NC} 清理旧备份: $(basename "$old")"
        rm -rf "$old"
    fi
done

echo -e "  ${BLUE}→${NC} 复制到 /Applications/..."
cp -R "${SCRIPT_DIR}/iFanControl.app" /Applications/
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 应用安装失败${NC}"
    exit 1
fi

sudo xattr -cr /Applications/iFanControl.app 2>/dev/null || true

if [ -d "/Applications/iFanControl.app" ]; then
    APP_SUCCESS=true
echo -e "${GREEN}✓${NC} 应用安装成功"
else
    echo -e "${RED}✗ 应用安装验证失败${NC}"
    exit 1
fi

if [ "$WAS_RUNNING" = true ]; then
    echo -e "  ${BLUE}→${NC} 正在重新启动 iFanControl..."
    open -n /Applications/iFanControl.app 2>/dev/null || true
    sleep 1
fi
echo ""

# ============================================
# 验证免密功能
# ============================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}🔍 验证安装结果...${NC}"
echo ""

sudo -n /usr/local/bin/kentsmc -r FNum &>/dev/null
if [ $? -eq 0 ]; then
    SUDO_SUCCESS=true
    echo -e "${GREEN}✓${NC} 免密授权测试成功"
else
    echo -e "${YELLOW}⚠${NC} 免密授权可能需要重启后生效"
fi
echo ""

# ============================================
# 安装状态总结
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

# ============================================
# 权限引导（关键！）
# ============================================
echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║              🔐 首次启动权限设置引导                      ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}正在准备首次启动权限...${NC}"
echo ""

# 步骤 1: 尝试打开应用（触发 Gatekeeper 拦截）
echo -e "  ${BLUE}→${NC} 正在启动 iFanControl.app（会触发安全提示）..."
open /Applications/iFanControl.app 2>/dev/null
OPEN_APP_STATUS=$?

sleep 1

# 步骤 2: 打开系统设置的隐私与安全性页面
echo -e "  ${BLUE}→${NC} 正在打开系统设置..."
open "x-apple.systempreferences:com.apple.preference.security" 2>/dev/null
OPEN_SETTINGS_STATUS=$?

sleep 1

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 根据执行结果显示不同提示
if [ $OPEN_APP_STATUS -eq 0 ] && [ $OPEN_SETTINGS_STATUS -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  👇 请按以下步骤操作 👇                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}第 1 步：${NC}在弹出的对话框中点击「打开」"
    echo -e "           如果没有弹出对话框，请继续第 2 步"
    echo ""
    echo -e "  ${YELLOW}第 2 步：${NC}在刚刚打开的「隐私与安全性」设置页面中"
    echo -e "           向下滚动找到「安全性」区域"
    echo ""
    echo -e "  ${YELLOW}第 3 步：${NC}找到「iFanControl.app 已被阻止」的提示"
    echo -e "           点击旁边的 ${GREEN}「仍要打开」${NC} 按钮"
    echo ""
    echo -e "  ${YELLOW}第 4 步：${NC}在确认对话框中点击「打开」"
    echo ""
    echo -e "  ${CYAN}完成以上步骤后，以后双击即可直接运行！${NC}"
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                  👇 请按以下步骤操作 👇                   ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}第 1 步：${NC}打开 Finder → 应用程序"
    echo ""
    echo -e "  ${YELLOW}第 2 步：${NC}双击 ${CYAN}iFanControl.app${NC}"
    echo -e "           （如果显示安全警告，不用担心）"
    echo ""
    echo -e "  ${YELLOW}第 3 步：${NC}打开「系统设置」→「隐私与安全性」"
    echo -e "           （可按 ${CYAN}⌘ + 空格${NC} 搜索「隐私」）"
    echo ""
    echo -e "  ${YELLOW}第 4 步：${NC}在「安全性」区域找到 iFanControl"
    echo -e "           点击 ${GREEN}「仍要打开」${NC}"
    echo ""
    echo -e "  ${YELLOW}第 5 步：${NC}在确认对话框中点击「打开」"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}完成后，应用会出现在菜单栏，显示温度和风扇转速！${NC}"
echo ""
echo -e "${BLUE}如遇问题，可运行 ${CYAN}diagnose.sh${NC} 进行诊断${NC}"
echo ""
read -p "按回车键退出..."
