#!/bin/bash

# iFanControl 安装启动器
# 注意：从网络下载后，.command 可能被 macOS 持续拦截。
# 推荐方式：打开终端，将 install.sh 拖入终端并回车执行。

cd "$(dirname "$0")"
chmod +x install.sh
exec ./install.sh
