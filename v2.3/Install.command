#!/bin/bash

# iFanControl 安装启动器
# 双击此文件即可开始安装

# 获取脚本所在目录
cd "$(dirname "$0")"

# 确保 install.sh 有执行权限
chmod +x install.sh

# 运行安装脚本
./install.sh
