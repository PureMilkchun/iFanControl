#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
cd "$SCRIPT_DIR" || exit 1
chmod +x ./uninstall.sh 2>/dev/null || true
exec ./uninstall.sh
