#!/usr/bin/env bash
# 老计聊SRE 数据采集脚本 2(过载拐点 / 稳态基线 / 自愈验证)
# 结果输出到 sli-dataset2.log。
#
# 用法(在 EC2 上,应用监听 localhost:8000;自愈测试需要 sudo 杀服务):
#   sudo bash collect-sli-dataset2.sh 2>&1 | tee sli-dataset2.log
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"

echo "############ 采集2 开始 $(date -u) ############"
echo "环境: $(uname -n) / $BASE_URL"
echo

# ========== [F] 过载拐点(给09容量/11混沌) ==========
# 逐级加大并发,找到吞吐不再上升、延迟开始飙升、甚至开始失败的拐点
echo "===== [F] 过载拐点(并发逐级加大) ====="
for conc in 50 100 200 400 800; do
  wd="$(mktemp -d)"; start=$(date +%s%N)
  seq 1 400 | xargs -P "$conc" -I{} curl -s -o /dev/null --max-time 10 \
    -w '%{http_code} %{time_total}\n' "${BASE_URL}/work" >> "$wd/f.txt" 2>/dev/null || true
  end=$(date +%s%N); ms=$(( (end-start)/1000000 ))
  python3 - "$wd/f.txt" "$conc" "$ms" <<'PY'
import sys
lines=[l.split() for l in open(sys.argv[1]) if l.strip()]
lat=sorted(float(x[1]) for x in lines if len(x)==2)
ok=sum(1 for x in lines if len(x)==2 and x[0].startswith("2"))
fail=sum(1 for x in lines if len(x)==2 and (x[0].startswith("5") or x[0]=="000"))
n=len(lines); ms=int(sys.argv[3])
pct=lambda v,p: v[min(len(v)-1,round((len(v)-1)*p))] if v else 0
qps=n/(ms/1000) if ms>0 else 0
print(f"[F-并发{sys.argv[2]}] 请求{n} 成功{ok} 失败{fail} 吞吐{qps:.1f}req/s "
      f"P50 {pct(lat,.5)*1000:.0f}ms P95 {pct(lat,.95)*1000:.0f}ms P99 {pct(lat,.99)*1000:.0f}ms")
PY
  rm -rf "$wd"
done
echo

# ========== [G] 稳态基线(给04错误预算) ==========
# 持续跑一段低错误率流量,得到"正常状态"的真实错误率基线
echo "===== [G] 稳态基线(低错误率,持续采样) ====="
wd="$(mktemp -d)"
for _ in $(seq 1 1000); do
  r=$((RANDOM % 100))
  # 90% 正常, 10% 打flaky(仅1%出错概率),模拟平时的低错误
  if [ "$r" -lt 90 ]; then path="/work"; else path="/flaky?rate=0.01"; fi
  curl -s -o /dev/null -w '%{http_code}\n' "${BASE_URL}${path}" >> "$wd/g.txt" 2>/dev/null || echo "000" >> "$wd/g.txt"
done
python3 - "$wd/g.txt" <<'PY'
import sys
codes=[c.strip() for c in open(sys.argv[1]) if c.strip()]
n=len(codes); ok=sum(1 for c in codes if c.startswith("2"))
err=n-ok
print(f"[G-稳态基线] 总{n} 成功{ok} 错误{err} 可用性{ok/n*100:.2f}% 错误率{err/n*100:.3f}%")
PY
rm -rf "$wd"
echo

# ========== [H] 自愈验证(给08健康检查/01自愈) ==========
# 后台持续打流量,中途杀掉应用,观察 systemd 自动拉起,统计恢复情况
echo "===== [H] 自愈验证(杀进程看systemd自动恢复) ====="
wd="$(mktemp -d)"
# 后台:持续20秒每0.2秒打一次健康检查,记录时间戳和结果
(
  end=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    ts=$(date +%s.%N)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${BASE_URL}/health" 2>/dev/null || echo "000")
    echo "$ts $code" >> "$wd/h.txt"
    sleep 0.2
  done
) &
bg_pid=$!

sleep 5
echo ">> 5秒后杀掉应用(systemctl kill sre-demo)"
kill_ts=$(date +%s.%N)
systemctl kill sre-demo || true
echo ">> 已杀,观察 systemd Restart=always 是否自动拉起"

wait "$bg_pid"

python3 - "$wd/h.txt" "$kill_ts" <<'PY'
import sys
rows=[l.split() for l in open(sys.argv[1]) if l.strip()]
kill_ts=float(sys.argv[2])
total=len(rows)
ok=sum(1 for _,c in rows if c.startswith("2"))
fail=sum(1 for _,c in rows if not c.startswith("2"))
# 找杀掉后第一个失败和恢复后第一个成功
after=[(float(t),c) for t,c in rows if float(t)>=kill_ts]
first_fail=next((t for t,c in after if not c.startswith("2")), None)
recover=next((t for t,c in after if not c.startswith("2")), None)
# 恢复点:失败之后第一个重新成功的
seen_fail=False; recover_ts=None
for t,c in after:
    if not c.startswith("2"): seen_fail=True
    elif seen_fail and c.startswith("2"): recover_ts=float(t); break
print(f"[H-自愈] 采样{total} 成功{ok} 失败{fail}")
if first_fail and recover_ts:
    print(f"[H-自愈] 杀掉到首次失败 {first_fail-kill_ts:.2f}s, 失败到恢复 {recover_ts-first_fail:.2f}s")
elif not fail:
    print("[H-自愈] 未捕捉到失败窗口(恢复太快或采样间隔太大)")
PY
rm -rf "$wd"
echo
echo ">> 确认服务已恢复:"
systemctl is-active sre-demo || true
curl -s "${BASE_URL}/health"; echo
echo

echo "############ 采集2 结束 $(date -u) ############"
