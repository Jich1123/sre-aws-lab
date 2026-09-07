#!/usr/bin/env bash
# 老计聊SRE 11:混沌实验三阶段 SLI 采集
# 实例上执行。分别在注入前、注入中、恢复后各跑一次,存不同文件。
# 用法:
#   bash 11-collect.sh before   # 注入前基线
#   bash 11-collect.sh during   # 注入进行中(FIS实验运行时)
#   bash 11-collect.sh after    # 恢复后
set -Eeuo pipefail

PHASE="${1:?用法: bash 11-collect.sh before|during|after}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
OUT="$HOME/sre-evidence/11-${PHASE}.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/sre-evidence"
{
  echo "==== 11 混沌实验 阶段: ${PHASE} ===="
  date
  BASE_URL="$BASE_URL" bash "${SCRIPT_DIR}/measure-sli.sh"
} 2>&1 | tee "$OUT"
echo "已存 $OUT"
