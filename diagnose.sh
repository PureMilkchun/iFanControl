#!/bin/bash

# iFanControl 安装诊断脚本
# 用户友好版本

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 状态计数
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

clear 2>/dev/null || true
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║            🔍 iFanControl 安装诊断工具                    ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}正在检查安装状态...${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查 1: kentsmc 是否安装
echo -e "${YELLOW}[1/5]${NC} 检查 kentsmc 工具..."
if [ -f "/usr/local/bin/kentsmc" ]; then
    echo -e "  ${GREEN}✓${NC} kentsmc 已安装"
    echo -e "    路径: /usr/local/bin/kentsmc"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}✗${NC} kentsmc 未安装"
    echo -e "    ${YELLOW}→ 请重新运行安装脚本${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# 检查 2: sudoers 配置
echo -e "${YELLOW}[2/5]${NC} 检查免密授权配置..."
if [ -f "/private/etc/sudoers.d/kentsmc" ]; then
    echo -e "  ${GREEN}✓${NC} 免密配置文件存在"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}✗${NC} 免密配置文件不存在"
    echo -e "    ${YELLOW}→ 请重新运行安装脚本${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# 检查 3: 应用是否安装
echo -e "${YELLOW}[3/5]${NC} 检查应用程序..."
if [ -d "/Applications/iFanControl.app" ]; then
    echo -e "  ${GREEN}✓${NC} iFanControl.app 已安装"
    echo -e "    路径: /Applications/iFanControl.app"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}✗${NC} iFanControl.app 未安装"
    echo -e "    ${YELLOW}→ 请重新运行安装脚本${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# 检查 4: 温度读取测试
echo -e "${YELLOW}[4/5]${NC} 测试温度读取功能..."
if [ -f "/usr/local/bin/kentsmc" ]; then
    TEMP_OUTPUT=$(/usr/local/bin/kentsmc -r FNum 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$TEMP_OUTPUT" ]; then
        echo -e "  ${GREEN}✓${NC} 温度读取成功"
        echo -e "    当前温度: ${CYAN}$TEMP_OUTPUT${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} 温度读取失败"
        echo -e "    ${YELLOW}→ 这可能是正常的，取决于系统状态${NC}"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} 跳过（kentsmc 未安装）"
    WARN_COUNT=$((WARN_COUNT + 1))
fi
echo ""

# 检查 5: 免密执行测试
echo -e "${YELLOW}[5/5]${NC} 测试免密执行..."
if [ -f "/usr/local/bin/kentsmc" ] && [ -f "/private/etc/sudoers.d/kentsmc" ]; then
    sudo -n /usr/local/bin/kentsmc -r FNum &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} 免密执行成功"
        echo -e "    安装已完成，以后运行无需输入密码"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} 免密执行失败"
        echo -e "    ${YELLOW}→ 可能需要重启电脑后生效${NC}"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} 跳过（前置条件未满足）"
    WARN_COUNT=$((WARN_COUNT + 1))
fi
echo ""

# ============================================
# 诊断结论
# ============================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                       诊断结果                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}通过: $PASS_COUNT${NC}  ${YELLOW}警告: $WARN_COUNT${NC}  ${RED}失败: $FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ] && [ $WARN_COUNT -eq 0 ]; then
    echo -e "  ${GREEN}🎉 安装状态：完美！所有检查都通过了。${NC}"
    echo ""
    echo -e "  你现在可以："
    echo -e "  1. 打开 Finder → 应用程序"
    echo -e "  2. 双击 ${CYAN}iFanControl.app${NC} 启动应用"
elif [ $FAIL_COUNT -eq 0 ]; then
    echo -e "  ${YELLOW}⚠ 安装状态：基本正常，有一些警告。${NC}"
    echo ""
    echo -e "  应该可以正常使用。如果遇到问题："
    echo -e "  • 重启电脑可能解决免密问题"
    echo -e "  • 首次打开可能需要在系统设置中允许"
else
    echo -e "  ${RED}✗ 安装状态：安装未完成。${NC}"
    echo ""
    echo -e "  请重新运行安装："
    echo -e "  • 打开终端，将 ${CYAN}install.sh${NC} 拖入终端，按回车"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "按回车键退出..."
