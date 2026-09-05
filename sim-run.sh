#!/bin/bash
# shim → 总部 SSOT。模拟器编译/装/起/截图逻辑全在那边一份。
# 禁在这里加逻辑:加了就等于又把共享能力复制回来了(铁律 #5)。
exec $HOME/Dev/tools/dev/lib/tools/macapp/ios/sim-run.sh "$(cd "$(dirname "$0")" && pwd)" "$@"
