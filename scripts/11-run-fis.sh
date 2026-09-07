#!/usr/bin/env bash
# 老计聊SRE 11:创建 FIS 执行角色并用模板启动一次 CPU 压力混沌实验
# 本地执行(需 IAM 和 FIS 权限)。前提:实例装了 SSM Agent 且有 SSM 权限、打了 Project=laoji-sre-lab 标签。
#
# 用法:
#   REGION=us-east-1 bash 11-run-fis.sh
set -Eeuo pipefail

REGION="${REGION:-us-east-1}"
ROLE_NAME="laoji-sre-fis-role"
FIS_DIR="$(cd "$(dirname "$0")/../fis" && pwd)"

echo "1) 创建 FIS 执行角色 ${ROLE_NAME}(若已存在则跳过)"
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${FIS_DIR}/fis-trust-policy.json"
  # FIS 官方托管策略,允许操作 EC2 与通过 SSM 注入
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access || true
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorSSMAccess || true
fi
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "   RoleArn=$ROLE_ARN"

echo "2) 用模板创建 FIS 实验模板(替换占位符)"
TMP=$(mktemp)
sed -e "s#REPLACE_WITH_FIS_ROLE_ARN#${ROLE_ARN}#g" \
    -e "s#REGION::document#${REGION}::document#g" \
    "${FIS_DIR}/fis-cpu-stress-template.json" > "$TMP"
TEMPLATE_ID=$(aws fis create-experiment-template --cli-input-json "file://${TMP}" \
  --region "$REGION" --query experimentTemplate.id --output text)
echo "   TemplateId=$TEMPLATE_ID"

echo "3) 启动实验(CPU 压力 120s)"
date
EXP_ID=$(aws fis start-experiment --experiment-template-id "$TEMPLATE_ID" \
  --region "$REGION" --query experiment.id --output text)
echo "   ExperimentId=$EXP_ID"
echo "提示:实验运行期间,在实例上跑 11-collect.sh during 采集注入中的 SLI。"
echo "清理:aws fis delete-experiment-template --id $TEMPLATE_ID --region $REGION"
