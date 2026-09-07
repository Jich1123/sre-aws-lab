#!/usr/bin/env bash
# 老计聊SRE 10:在同一台实例上并行启动 v1(正常)和 v2(坏版本)
# v1 监听 8000,v2 监听 8001。用于金丝雀对比。
# 实例上执行(app 目录里要有 main.py 和 main_v2.py)。
set -Eeuo pipefail

APP_DIR="${APP_DIR:-$HOME/career-plan/sre/lab/app}"
cd "$APP_DIR"

# 确保依赖
python3 -m pip install -q -r requirements.txt

echo "启动 v1(正常版)在 :8000"
nohup uvicorn main:app --host 0.0.0.0 --port 8000 > /tmp/v1.log 2>&1 &
echo "启动 v2(金丝雀坏版本,/work 25% 概率500)在 :8001"
BAD_RATE=0.25 nohup uvicorn main_v2:app --host 0.0.0.0 --port 8001 > /tmp/v2.log 2>&1 &

sleep 3
echo "健康检查:"
curl -s http://localhost:8000/ | head -c 200; echo
curl -s http://localhost:8001/ | head -c 200; echo
echo "v1 日志 /tmp/v1.log , v2 日志 /tmp/v2.log"
