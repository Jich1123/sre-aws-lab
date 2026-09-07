#!/usr/bin/env bash
# 老计聊SRE 数据采集脚本(一次跑齐后面篇章要用的真实数据)
# 结果统一输出到 sli-dataset.log,分节标注,便于归类到各篇文章。
#
# 用法(在 EC2 上,应用监听 localhost:8000):
#   bash collect-sli-dataset.sh 2>&1 | tee sli-dataset.log
#
# 采集内容:
#   [A] 三档健康度SLI(给03 SLO)
#   [B] 纯延迟分布(给02/03)
#   [C] 并发压测(给09容量规划)
#   [D] 故障时间线(给05告警/07复盘)
#   [E] 资源指标对照(给排查)
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"

# ---------- 通用:发N个混合请求并统计 ----------
run_batch() {
  local total="$1" flaky_rate="$2" slow_ms="$3" label="$4"
  local wd; wd="$(mktemp -d)"
  for _ in $(seq 1 "$total"); do
    local r=$((RANDOM % 100)) path
    if   [ "$r" -lt 70 ]; then path="/work"
    elif [ "$r" -lt 85 ]; then path="/slow?ms=${slow_ms}"
    else path="/flaky?rate=${flaky_rate}"
    fi
    curl -s -o /dev/null -w '%{http_code} %{time_total}\n' "${BASE_URL}${path}" \
      >> "$wd/r.txt" 2>/dev/null || echo "000 0" >> "$wd/r.txt"
  done
  python3 - "$wd/r.txt" "$label" <<'PY'
import sys
lines=[l.split() for l in open(sys.argv[1]) if l.strip()]
codes=[c for c,_ in lines]; lat=sorted(float(t) for _,t in lines)
total=len(lines); succ=sum(1 for c in codes if c.startswith("2"))
err=sum(1 for c in codes if c.startswith("5") or c=="000")
pct=lambda v,p: v[min(len(v)-1,round((len(v)-1)*p))] if v else 0
print(f"[{sys.argv[2]}] 总{total} 成功{succ} 错误{err} "
      f"可用性{succ/total*100:.2f}% 错误率{err/total*100:.2f}% "
      f"平均{sum(lat)/len(lat)*1000:.0f}ms P50 {pct(lat,.5)*1000:.0f}ms "
      f"P95 {pct(lat,.95)*1000:.0f}ms P99 {pct(lat,.99)*1000:.0f}ms")
PY
  rm -rf "$wd"
}

echo "############ 采集开始 $(date -u) ############"
echo "环境: $(uname -n) / $BASE_URL"
echo

# ========== [A] 三档健康度SLI(给03 SLO) ==========
echo "===== [A] 三档健康度SLI ====="
run_batch 500 0.02 100 "A-健康 flaky2% slow100ms"
run_batch 500 0.10 300 "A-一般 flaky10% slow300ms"
run_batch 500 0.40 800 "A-较差 flaky40% slow800ms"
echo

# ========== [B] 纯延迟分布(给02/03) ==========
echo "===== [B] 纯延迟分布(只打/slow,不同延迟档) ====="
for ms in 50 200 500 1000; do
  wd="$(mktemp -d)"
  for _ in $(seq 1 100); do
    curl -s -o /dev/null -w '%{time_total}\n' "${BASE_URL}/slow?ms=${ms}" >> "$wd/t.txt" 2>/dev/null || true
  done
  python3 - "$wd/t.txt" "$ms" <<'PY'
import sys
lat=sorted(float(x) for x in open(sys.argv[1]) if x.strip())
pct=lambda v,p: v[min(len(v)-1,round((len(v)-1)*p))] if v else 0
print(f"[B-slow {sys.argv[2]}ms] P50 {pct(lat,.5)*1000:.0f}ms "
      f"P95 {pct(lat,.95)*1000:.0f}ms P99 {pct(lat,.99)*1000:.0f}ms")
PY
  rm -rf "$wd"
done
echo

# ========== [C] 并发压测(给09容量规划) ==========
echo "===== [C] 并发压测(不同并发下的延迟与吞吐) ====="
for conc in 1 10 50 100; do
  wd="$(mktemp -d)"; start=$(date +%s%N)
  seq 1 200 | xargs -P "$conc" -I{} curl -s -o /dev/null \
    -w '%{http_code} %{time_total}\n' "${BASE_URL}/work" >> "$wd/c.txt" 2>/dev/null || true
  end=$(date +%s%N); elapsed_ms=$(( (end-start)/1000000 ))
  python3 - "$wd/c.txt" "$conc" "$elapsed_ms" <<'PY'
import sys
lines=[l.split() for l in open(sys.argv[1]) if l.strip()]
lat=sorted(float(x[1]) for x in lines if len(x)==2)
n=len(lines); ms=int(sys.argv[3])
pct=lambda v,p: v[min(len(v)-1,round((len(v)-1)*p))] if v else 0
qps=n/(ms/1000) if ms>0 else 0
print(f"[C-并发{sys.argv[2]}] 请求{n} 总耗时{ms}ms 吞吐{qps:.1f}req/s "
      f"P50 {pct(lat,.5)*1000:.0f}ms P95 {pct(lat,.95)*1000:.0f}ms P99 {pct(lat,.99)*1000:.0f}ms")
PY
  rm -rf "$wd"
done
echo

# ========== [D] 故障时间线(给05告警/07复盘) ==========
echo "===== [D] 故障时间线(健康->故障->恢复,每阶段一组SLI) ====="
echo "阶段1 正常运行(flaky2%):"
run_batch 300 0.02 100 "D-t1-正常"
echo "阶段2 故障爆发(flaky60%):"
run_batch 300 0.60 500 "D-t2-故障"
echo "阶段3 恢复(flaky2%):"
run_batch 300 0.02 100 "D-t3-恢复"
echo

# ========== [E] 资源指标对照(给排查) ==========
echo "===== [E] 压测时的资源指标 ====="
echo "内存:"; free -m | head -2
echo "负载:"; uptime
echo "CPU核数:"; nproc
echo

echo "############ 采集结束 $(date -u) ############"
