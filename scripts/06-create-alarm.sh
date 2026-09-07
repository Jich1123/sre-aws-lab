#!/usr/bin/env bash
# 老计聊SRE 06:创建 SNS 主题+邮箱订阅,并创建基于错误率的 CloudWatch 告警
# 本地执行(需 SNS 和 CloudWatch 权限)。
#
# 用法:
#   REGION=us-east-1 EMAIL=you@example.com bash 06-create-alarm.sh
# 产出:打印 TopicArn;创建告警 sre-error-rate-high(错误率>5% 触发,发到SNS)
set -Eeuo pipefail

REGION="${REGION:-us-east-1}"
EMAIL="${EMAIL:?请设置 EMAIL 环境变量,例如 EMAIL=you@example.com}"
TOPIC_NAME="sre-oncall-demo"
ALARM_NAME="sre-error-rate-high"
NAMESPACE="SREDemo"
METRIC="ErrorRate"

echo "1) 创建 SNS 主题 ${TOPIC_NAME}"
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC_NAME" --region "$REGION" --output text --query TopicArn)
echo "   TopicArn=$TOPIC_ARN"

echo "2) 订阅邮箱 ${EMAIL}(去邮箱点确认链接后订阅才生效)"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email \
  --notification-endpoint "$EMAIL" --region "$REGION"

echo "3) 创建告警 ${ALARM_NAME}(错误率>5% 持续1个周期即触发)"
aws cloudwatch put-metric-alarm \
  --alarm-name "$ALARM_NAME" \
  --alarm-description "示例应用错误率过高,基于错误预算的症状告警" \
  --namespace "$NAMESPACE" --metric-name "$METRIC" \
  --statistic Average --period 60 --evaluation-periods 1 \
  --threshold 5 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --region "$REGION"

echo "完成。TopicArn=$TOPIC_ARN"
echo "提示:先去邮箱确认订阅,再在实例上跑 06-report-error-rate.sh 制造高错误率触发告警。"
echo "清理:aws cloudwatch delete-alarms --alarm-names $ALARM_NAME --region $REGION"
echo "     aws sns delete-topic --topic-arn $TOPIC_ARN --region $REGION"
