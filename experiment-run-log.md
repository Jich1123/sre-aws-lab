# 老计聊SRE 实验实况记录

> 按时间记录真实操作与返回结果,用于撰写系列文章。
> 环境:AWS EC2 t3.micro,Ubuntu 22.04,us-east-1,跑 FastAPI 示例应用。

## 实验环境

- 实例ID:i-01c07663bdb7b15df
- 公网IP:54.227.89.242
- 机型:t3.micro(2 vCPU / 1GB,免费额度内)
- 应用地址:http://54.227.89.242:8000
- 健康检查:http://54.227.89.242:8000/health
- 安全组:sg-00f007b5b50267656(22端口给跳板机+本地,8000给本地浏览器)
- 创建时间:2026-09-01 约 10:28

---

## 第01篇:示例应用部署

### 1.1 terraform apply

```bash
cd sre/lab/terraform
terraform apply -auto-approve
```

结果:3 added(密钥对、安全组、EC2 实例),约16秒完成。输出:
- public_ip = 54.227.89.242
- app_url = http://54.227.89.242:8000
- ssh_command = ssh ubuntu@54.227.89.242

开机脚本(user_data)会自动:装 python3-venv、写入 FastAPI 应用、pip 装 fastapi+uvicorn、用 systemd 启动 sre-demo 服务。部署完成标志:/var/log/sre-demo-userdata-done。

### 1.2 首次部署失败:user_data heredoc 缩进问题(真实踩坑)

首次开机后 `/var/log/sre-demo-userdata-done` 不存在,cloud-init-output.log 显示:

```
cc_scripts_user.py[WARNING]: Failed to run module scripts_user
Running module scripts_user ... failed
```

开机16秒就失败退出,没执行到装依赖。

根因(两个):
1. terraform 的 `user_data = <<-EOF` 用 `<<-` 只去除行首 Tab,但这里是空格缩进,导致脚本每行(含 `#!/usr/bin/env bash`)行首带空格,shebang 失效。
2. 内嵌的 systemd 单元 heredoc 用 `<<'SVCEOF'`(未加 `-`),但结束标记 `SVCEOF` 前有缩进空格,bash 找不到结束标记,脚本语法崩溃。

修复:user_data 改为**顶格书写**(不缩进),内嵌 heredoc 的结束标记也顶格;并加 `exec > /var/log/sre-demo-deploy.log 2>&1` 把部署输出单独存一份便于排查;加 `user_data_replace_on_change = true` 让脚本变更时自动重建实例。

这个坑很有 SRE 价值:自动化脚本"看起来会跑",但没有验证和日志就发现不了失败。第01篇可点出"自动化 + 可观测"的重要性。

### 1.3 重建实例

修复后 apply,实例因 user_data 变化被重建:
- 新实例ID:i-06d8b0e90add03f56
- 新公网IP:98.93.182.90(重建导致IP变化,安全组和密钥对不变)
- 应用地址:http://98.93.182.90:8000


### 1.4 部署成功验证

修复后重新部署,本地浏览器访问 http://98.93.182.90:8000/ 成功返回(截图 sre/logs/ec2-start-test.png):

```json
{
  "service": "laoji-sre-demo",
  "version": "1.0.0",
  "host": "ip-172-31-23-150",
  "uptime_seconds": 58.6,
  "message": "老计聊SRE 系列示例应用"
}
```

结论:示例应用部署成功,FastAPI 服务由 systemd 托管、监听 8000,可从本地浏览器访问。全系列的实验对象就绪。

第01篇可用的真实素材:
- terraform apply 输出(3资源、t3.micro、免费额度)
- user_data 缩进导致的静默失败 + 排查(cloud-init-output.log 的 scripts_user failed)+ 修复
- 修复后成功访问的 JSON 返回
- 引出的 SRE 观点:自动化必须配合日志与验证,否则"看起来配好了"其实失败了

（新实例信息:i-06d8b0e90add03f56 / 98.93.182.90 / host ip-172-31-23-150）

---

## 第02篇:SLI 度量

### 2.1 用混合流量测出真实 SLI

脚本 measure-sli.sh 对示例应用发 500 个混合请求(70% /work 正常、15% /slow 延迟300ms、15% /flaky 20%概率出错):

```bash
BASE_URL=http://localhost:8000 bash measure-sli.sh
```

真实结果:

```
总请求:      500
成功(2xx):   482
错误(5xx等): 18
可用性 SLI:  96.40%
错误率:      3.60%
平均延迟:    39 ms
P50 延迟:    1 ms
P95 延迟:    302 ms
P99 延迟:    302 ms
```

数据解读(写入文章):
- 可用性 SLI 96.40%:500个请求18个失败,失败来自 /flaky 端点。这就是"从用户视角"的可用性,不是"服务器有没有宕机"。
- 平均延迟 39ms 具有欺骗性:P50 只有 1ms(大部分 /work 请求极快),但 P95/P99 到了 302ms(被 /slow 的300ms拉高)。这说明**平均值会掩盖长尾,SLI 必须看分位数**。
- 这组数据天然引出 SLO:96.4% 的可用性够不够?302ms 的 P95 可接受吗?要回答这些,就需要给 SLI 定目标(SLO),即第03篇。

---

## 后续篇章数据集(collect-sli-dataset.sh 一次采齐,2026-09-01)

原始结果:sre/logs/sli-dataset.log。环境 ip-172-31-23-150,t3.micro(2核/914MB)。

### [A] 三档健康度SLI(给03 SLO)
- 健康(flaky2%/slow100): 可用性99.60% 错误率0.40% P95 102ms
- 一般(flaky10%/slow300): 可用性97.80% 错误率2.20% P95 302ms
- 较差(flaky40%/slow800): 可用性93.80% 错误率6.20% P95 802ms

### [B] 纯延迟分布(给02/03)
- slow50→P95 52ms;slow200→202ms;slow500→502ms;slow1000→1003ms
- 说明:延迟端点设多少,P95就贴着多少,分位数如实反映真实延迟。

### [C] 并发压测(给09容量规划)
- 并发1:吞吐134 req/s,P99 1ms
- 并发10:吞吐186,P99 18ms
- 并发50/100:吞吐~184-186,P99 18-19ms
- 说明:并发从1→10吞吐上升后趋于平台(~186 req/s),说明单进程uvicorn的处理上限在这附近;/work很轻,延迟增加有限。t3.micro 2核,并发再高吞吐不再涨,这是容量上限的真实体现。

### [D] 故障时间线(给05告警/07复盘)
- t1正常:可用性99.67% 错误率0.33%
- t2故障(flaky60%):可用性88.00% 错误率12.00% P95 502ms
- t3恢复:可用性100% 错误率0%
- 说明:完整的"健康→故障→恢复"三段,错误率从0.33%突增到12%再回落。这是告警阈值设定(第05篇)和故障复盘时间线(第07篇)的真实素材。

### [E] 资源指标(给排查)
- 内存914MB(t3.micro),压测时used约203MB,available 535MB
- 负载 load average 0.49(2核),CPU没有打满
- 说明:压测期间资源很闲(CPU没满、内存够),但SLI仍有波动——印证第02篇"资源指标健康≠服务可靠",错误来自应用逻辑(/flaky)而非资源瓶颈。

---

## 数据集2(collect-sli-dataset2.sh,2026-09-01)

原始结果:sre/logs/sli-dataset2.log。

### [F] 过载拐点(给09容量/11混沌)
- 并发50→800,吞吐稳定在 181-186 req/s,零失败,P95/P99 稳定在 14-22ms
- 说明:/work 太轻量,即使并发800,这台t3.micro也没被压垮,吞吐平台稳定在~185 req/s(处理上限),延迟没有明显劣化,无失败。结论:该服务的瓶颈是单进程吞吐(~185 req/s),而非并发承载;要提吞吐需要多worker/多实例。这本身是容量规划的真实结论:先找到瓶颈在哪。

### [G] 稳态基线(给04错误预算)
- 1000请求,可用性99.90%,错误率0.100%
- 说明:正常状态下的真实错误率基线约0.1%。第04篇讲错误预算时,可用这个基线说明"平时以很低速率消耗预算,故障时才会快速烧掉"。

### [H] 自愈验证(给08健康检查/01自愈)⭐
- 后台每0.2s打一次/health,共采样90次:成功86、失败4
- 杀掉应用后 0.12s 出现首次失败,失败到恢复仅 0.86s
- 恢复后 systemctl is-active = active,/health 返回 {"status":"ok"}
- 说明:systemd 的 Restart=always 在应用被杀后不到1秒就自动拉起了服务,期间只有约4个请求(约0.8秒窗口)失败。这是"自愈"最直观的真实演示:进程级故障靠 systemd 自动恢复,MTTR(平均恢复时间)不到1秒。第08篇(健康检查与优雅降级)的核心素材,也回扣第01篇提到的 Restart=always。
- 注意:这只是进程级自愈;若整台机器挂了,systemd 救不了,需要更高层(多实例/健康检查+负载均衡剔除),这正是08篇要往下讲的。
