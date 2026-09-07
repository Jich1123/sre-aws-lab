#!/usr/bin/env bash
# 老计聊SRE 10:金丝雀对比,只打 /work 分别压 v1 和 v2,对比错误率
# 直接对两个端口压测,清楚看到 v2(坏版本)错误率明显更高。
# 实例上执行。
set -Eeuo pipefail

V1="${V1:-http://localhost:8000}"
V2="${V2:-http://localhost:8001}"
N="${N:-300}"

measure() {
  local base="$1" name="$2"
  local err=0
  for i in $(seq 1 "$N"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "${base}/work" || echo 000)
    if [[ "$code" == 5* || "$code" == "000" ]]; then err=$((err+1)); fi
  done
  local rate; rate=$(python3 -c "print(round(${err}/${N}*100,2))")
  echo "${name}: 总请求 ${N}  失败 ${err}  错误率 ${rate}%"
}

echo "== 金丝雀错误率对比(每版本 ${N} 个 /work 请求) =="
date
measure "$V1" "v1 正常版 (:8000)"
measure "$V2" "v2 金丝雀 (:8001)"
echo "结论:v2 错误率应明显高于 v1,金丝雀阶段即可据此决定回滚。"
