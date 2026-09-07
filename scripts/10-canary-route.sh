#!/usr/bin/env bash
# 老计聊SRE 10:纯双端口金丝雀演示(不依赖ALB,零云端配置)
# 用一个脚本按权重把请求分到 v1(8000) 和 v2(8001),模拟金丝雀导流,
# 分别统计两版本的错误率;再演示把权重切回全 v1 的"回滚"。
#
# 实例上执行(先用 10-start-two-versions.sh 起好 v1 v2)。
# 用法:
#   金丝雀阶段(v2 导 10%):  WEIGHT_V2=10 N=500 bash 10-canary-route.sh
#   回滚后(v2 导 0%):       WEIGHT_V2=0  N=500 bash 10-canary-route.sh
set -Eeuo pipefail

V1="${V1:-http://localhost:8000}"
V2="${V2:-http://localhost:8001}"
WEIGHT_V2="${WEIGHT_V2:-10}"     # 分到 v2 的百分比(金丝雀比例)
N="${N:-500}"                    # 总请求数

v1_total=0; v1_err=0
v2_total=0; v2_err=0

echo "== 金丝雀分流演示:v2 权重 ${WEIGHT_V2}% ,总请求 ${N} =="
date

for i in $(seq 1 "$N"); do
  r=$((RANDOM % 100))
  if [ "$r" -lt "$WEIGHT_V2" ]; then
    base="$V2"; tag=v2
  else
    base="$V1"; tag=v1
  fi
  code=$(curl -s -o /dev/null -w '%{http_code}' "${base}/work" || echo 000)
  if [ "$tag" = v1 ]; then
    v1_total=$((v1_total+1))
    [[ "$code" == 5* || "$code" == "000" ]] && v1_err=$((v1_err+1)) || true
  else
    v2_total=$((v2_total+1))
    [[ "$code" == 5* || "$code" == "000" ]] && v2_err=$((v2_err+1)) || true
  fi
done

rate() { [ "$2" -eq 0 ] && echo "n/a" || python3 -c "print(round($1/$2*100,2))"; }

echo "----------------------------------------"
echo "v1 正常版 :8000  请求 ${v1_total}  失败 ${v1_err}  错误率 $(rate $v1_err $v1_total)%"
echo "v2 金丝雀 :8001  请求 ${v2_total}  失败 ${v2_err}  错误率 $(rate $v2_err $v2_total)%"
echo "----------------------------------------"
echo "解读:v2 错误率明显高于 v1,说明这次发布引入了故障;"
echo "     此时应把 v2 权重切回 0(即回滚),再跑一次 WEIGHT_V2=0 验证整体错误率恢复。"
