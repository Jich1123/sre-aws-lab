#!/usr/bin/env bash
# 老计聊SRE 06:把示例应用的错误率上报到 CloudWatch 自定义指标
# 思路:持续对服务打一批混合流量,算出这批的错误率,作为一个数据点
#       上报到 CloudWatch 的 SREDemo/ErrorRate 指标,供告警使用。
# 在实例上后台跑这个脚本,配合 06-create-alarm.sh 创建的告警,即可演示"错误率高->告警"。
#
# 用法(实例上执行,需实例有 cloudwatch:PutMetricData 权限):
#   REGION=us-east-1 BASE_URL=http://localhost:8000 FLAKY_RATE=0.6 bash 06-report-error-rate.sh
#   FLAKY_RATE 调高(如0.6)模拟故障;调低(如0.02)模拟正常。
set -Eeuo pipefail

REGION="${REGION:-us-east-1}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
FLAKY_RATE="${FLAKY_RATE:-0.6}"      # 打到 /flaky 的错误概率
BATCH="${BATCH:-100}"                # 每轮请求数
INTERVAL="${INTERVAL:-60}"           # 每轮间隔秒(与告警period对齐)
NAMESPACE="SREDemo"
METRIC="ErrorRate"

echo "开始上报错误率到 CloudWatch ${NAMESPACE}/${METRIC},每 ${INTERVAL}s 一轮,每轮 ${BATCH} 请求,FLAKY_RATE=${FLAKY_RATE}"
echo "按 Ctrl+C 停止。"

while true; do
  errors=0
  for i in $(seq 1 "$BATCH"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/flaky?rate=${FLAKY_RATE}" || echo 000)
    if [[ "$code" == 5* || "$code" == "000" ]]; then errors=$((errors+1)); fi
  done
  rate=$(python3 -c "print(round(${errors}/${BATCH}*100, 2))")
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$(date '+%F %T')  错误率 ${rate}%  (${errors}/${BATCH})"
  aws cloudwatch put-metric-data \
    --namespace "$NAMESPACE" --metric-name "$METRIC" \
    --value "$rate" --unit Percent --timestamp "$ts" \
    --region "$REGION"
  sleep "$INTERVAL"
done
