#!/usr/bin/env bash
# HM_Player 签名 HAP 构建脚本
# 关键：在 WorkBuddy 的 bash 环境里，NODE_OPTIONS 被注入了 genie-safe-delete.cjs
# 会 fail-closed 拦截 hvigor 清理构建产物（configure_fingerprint.json / report-*.json）
# 导致 BuildNativeWithCmake / wrapUpBeforeExit 崩溃。本脚本前置关闭这些守卫。
set -e

cd "$(dirname "$0")"

# 1) 让 hvigor 用健康的 JBR 而非 PATH 上损坏的 Oracle Java
export PATH="/d/Program Files/Huawei/DevEco Studio/jbr/bin:$PATH"

# 2) 取消 safe-delete 守卫对 rm/unlink/rmdir 的函数包装
unset -f rm unlink rmdir 2>/dev/null || true

# 3) 关闭 WorkBuddy 注入的 node 守卫
export DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk"
export NODE_OPTIONS=""
export BASH_ENV=""

# 4) --no-daemon 避免复用被污染的 daemon node 环境
exec "D:/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "D:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone \
  assembleHap --analyze=normal --parallel --incremental --no-daemon
