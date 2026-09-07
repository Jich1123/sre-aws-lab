"""
老计聊SRE 系列示例应用 v2(坏版本,仅用于第10篇金丝雀演示)

与 app/main.py(v1 正常版)的唯一区别:/work 端点按概率返回 500,
用来模拟一次"引入了故障的发布",在金丝雀阶段被更高错误率暴露出来。

启动(实例上,与 v1 并行跑在不同端口):
  uvicorn main_v2:app --host 0.0.0.0 --port 8001
说明:这是教学演示故意做的坏版本,不是生产做法。
"""
from fastapi import FastAPI, Response, Query
import time
import random
import os

app = FastAPI(title="laoji-sre-demo", version="2.0.0-canary")

START_TIME = time.time()
HOSTNAME = os.uname().nodename

# v2 引入的故障:/work 有这个概率直接返回 500
BAD_RATE = float(os.environ.get("BAD_RATE", "0.25"))


@app.get("/")
def root():
    return {
        "service": "laoji-sre-demo",
        "version": "2.0.0-canary",
        "host": HOSTNAME,
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "message": "老计聊SRE 系列示例应用 v2 金丝雀版",
    }


@app.get("/health")
def health():
    # 注意:健康检查仍返回 ok,故障只体现在业务端点,
    # 这正是金丝雀要靠业务错误率而非健康检查来发现坏版本的原因。
    return {"status": "ok"}


@app.get("/work")
def work(response: Response):
    # v2 的故障:按 BAD_RATE 概率返回 500
    if random.random() < BAD_RATE:
        response.status_code = 500
        return {"status": "error", "version": "2.0.0-canary", "host": HOSTNAME}
    total = sum(i * i for i in range(1000))
    return {"result": total, "version": "2.0.0-canary", "host": HOSTNAME}


@app.get("/slow")
def slow(ms: int = Query(default=500, ge=0, le=10000)):
    time.sleep(ms / 1000.0)
    return {"slept_ms": ms, "host": HOSTNAME}


@app.get("/flaky")
def flaky(response: Response, rate: float = Query(default=0.3, ge=0.0, le=1.0)):
    if random.random() < rate:
        response.status_code = 500
        return {"status": "error", "host": HOSTNAME}
    return {"status": "ok", "host": HOSTNAME}
