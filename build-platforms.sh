#!/bin/bash
# shim → 总部 SSOT。三平台构建 / Mac 装机逻辑全在那边一份。
# 禁在这里加逻辑:加了就等于又把共享能力复制回来了(铁律 #5)。
exec /Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/build-platforms.sh "$(cd "$(dirname "$0")" && pwd)" "$@"
