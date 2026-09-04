#!/usr/bin/env bash
# 老计聊SRE 02:SLI 度量脚本
# 对示例应用打一批流量,从真实结果计算 SLI:
#   - 可用性(成功率) = 非5xx请求数 / 总请求数
#   - 延迟分布 P50/P95/P99
#   - 错误率
#
# 用法:
#   BASE_URL=http://localhost:8000 bash measure-sli.sh
#   可调:TOTAL(总请求数)、FLAKY_RATIO(打到/flaky的比例)、SLOW_MS(/slow延迟)
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
TOTAL="${TOTAL:-500}"
FLAKY_RATE="${FLAKY_RATE:-0.2}"     # /flaky 端点自身的错误概率
SLOW_MS="${SLOW_MS:-300}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "对 $BASE_URL 发起 $TOTAL 个请求(混合 /work 正常、/slow 延迟、/flaky 可能出错)"

for i in $(seq 1 "$TOTAL"); do
  # 混合流量:70% 正常/work,15% /slow,15% /flaky
  r=$((RANDOM % 100))
  if   [ "$r" -lt 70 ]; then path="/work"
  elif [ "$r" -lt 85 ]; then path="/slow?ms=${SLOW_MS}"
  else path="/flaky?rate=${FLAKY_RATE}"
  fi
  # 记录 HTTP状态码 和 总耗时(秒)
  curl -s -o /dev/null -w '%{http_code} %{time_total}\n' "${BASE_URL}${path}" \
    >> "$work_dir/results.txt" || echo "000 0" >> "$work_dir/results.txt"
done

echo "统计中..."
python3 - "$work_dir/results.txt" <<'PY'
import sys
lines = [l.split() for l in open(sys.argv[1]) if l.strip()]
codes = [c for c, _ in lines]
lat = sorted(float(t) for _, t in lines)
total = len(lines)
success = sum(1 for c in codes if c.startswith("2"))
errors  = sum(1 for c in codes if c.startswith("5") or c == "000")

def pct(v, p):
    if not v: return 0.0
    i = min(len(v)-1, round((len(v)-1)*p))
    return v[i]

print("=" * 44)
print(f"总请求:      {total}")
print(f"成功(2xx):   {success}")
print(f"错误(5xx等): {errors}")
print(f"可用性 SLI:  {success/total*100:.2f}%")
print(f"错误率:      {errors/total*100:.2f}%")
print(f"平均延迟:    {sum(lat)/len(lat)*1000:.0f} ms")
print(f"P50 延迟:    {pct(lat,0.50)*1000:.0f} ms")
print(f"P95 延迟:    {pct(lat,0.95)*1000:.0f} ms")
print(f"P99 延迟:    {pct(lat,0.99)*1000:.0f} ms")
print("=" * 44)
PY
