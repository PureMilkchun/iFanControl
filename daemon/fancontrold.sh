#!/bin/bash

# MacFanControl 守护进程
# 以 root 运行，通过命名管道接收命令

KENTSMC="/usr/local/bin/kentsmc"
CMD_PIPE="/tmp/mfc_command"
RESULT_FILE="/tmp/mfc_result"
LOCK_FILE="/tmp/mfc.lock"

# 清理旧的文件
rm -f "$CMD_PIPE" "$RESULT_FILE" "$LOCK_FILE"

# 创建命名管道
mkfifo "$CMD_PIPE"

# 设置权限（所有用户可写）
chmod 666 "$CMD_PIPE"

echo "[$(date)] fancontrold started" >> /tmp/mfc_daemon.log

# 主循环
while true; do
    # 等待命令（阻塞读取）
    if read -r cmd < "$CMD_PIPE"; then
        # 防止并发执行
        (
            flock -x 200
            
            result=""
            case "$cmd" in
                set_rpm_*)
                    rpm="${cmd#set_rpm_}"
                    result=$("$KENTSMC" --fan-rpm "$rpm" 2>&1)
                    ;;
                set_auto)
                    result=$("$KENTSMC" --fan-auto 2>&1)
                    ;;
                unlock_fans)
                    result=$("$KENTSMC" --unlock-fans 2>&1)
                    ;;
                read_temp)
                    result=$("$KENTSMC" -r Tp0e 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
                    ;;
                read_rpm)
                    result=$("$KENTSMC" -r F0Ac 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
                    ;;
                ping)
                    result="pong"
                    ;;
                *)
                    result="unknown_command"
                    ;;
            esac
            
            echo "$result" > "$RESULT_FILE"
            
        ) 200>"$LOCK_FILE"
    fi
done
