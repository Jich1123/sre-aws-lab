"""
老计聊SRE 系列示例应用
一个极简的 FastAPI HTTP 服务,作为全系列的实验对象。

端点:
- GET /            返回服务基本信息
- GET /health      健康检查(SRE 篇章会用到)
- GET /work        正常业务端点,返回一点计算结果
- GET /slow        可控延迟端点(用 ?ms=500 控制),用于演示延迟类 SLI
- GET /flaky       可控错误率端点(用 ?rate=0.3 控制),用于演示错误率 SLI 和告警

说明:这些"可控端点"是为了后续 SRE 实验能方便地制造延迟和错误,
不是生产做法,仅用于教学演示。
"""
from fastapi import FastAPI, Response, Query
import time
import random
import os

app = FastAPI(title="laoji-sre-demo", version="1.0.0")

START_TIME = time.time()
HOSTNAME = os.uname().nodename


@app.get("/")
def root():
    return {
        "service": "laoji-sre-demo",
        "version": "1.0.0",
        "host": HOSTNAME,
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "message": "老计聊SRE 系列示例应用",
    }


@app.get("/health")
def health():
    # 健康检查:真实项目里这里会检查依赖(数据库、缓存等),这里简化为always ok
    return {"status": "ok"}


@app.get("/work")
def work():
    # 模拟一点轻量业务计算
    total = sum(i * i for i in range(1000))
    return {"result": total, "host": HOSTNAME}


@app.get("/slow")
def slow(ms: int = Query(default=500, ge=0, le=10000)):
    # 可控延迟:用于演示延迟类 SLI(如 P95 延迟)
    time.sleep(ms / 1000.0)
    return {"slept_ms": ms, "host": HOSTNAME}


@app.get("/flaky")
def flaky(response: Response, rate: float = Query(default=0.3, ge=0.0, le=1.0)):
    # 可控错误率:按概率返回 500,用于演示错误率 SLI、错误预算和告警
    if random.random() < rate:
        response.status_code = 500
        return {"status": "error", "host": HOSTNAME}
    return {"status": "ok", "host": HOSTNAME}
