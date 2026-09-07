# 06 / 10 / 11 实操资产索引

本目录为 06、10、11 三篇预先备好的脚本、应用版本和 FIS 模板,配合 `open-machine-runbook.md` 使用,开机时直接跑。

## 文件清单

### 第06篇 On-call
- `scripts/06-create-alarm.sh`：本地跑,建 SNS 主题+邮箱订阅+基于错误率的 CloudWatch 告警。
- `scripts/06-report-error-rate.sh`：实例上跑,把实测错误率上报到 CloudWatch 自定义指标 SREDemo/ErrorRate,喂给告警。

### 第10篇 变更管理(金丝雀,纯双端口零云端配置)
- `app/main_v2.py`：坏版本应用,/work 按概率(默认25%)返回500,模拟一次引入故障的发布。
- `scripts/10-start-two-versions.sh`：实例上跑,v1 起在 8000、v2 起在 8001。
- `scripts/10-canary-route.sh`：实例上跑,按权重(如 v2 导10%)分流两版本并算错误率,回滚就把权重设0再跑一次。
- `scripts/10-canary-compare.sh`：实例上跑,直接分别压 v1/v2 看更干净的错误率对比。

### 第11篇 混沌工程(FIS)
- `fis/fis-trust-policy.json`：FIS 执行角色的信任策略。
- `fis/fis-stop-instance-template.json`：首选方案,停实例2分钟再自动启动,无 SSM 依赖。
- `fis/fis-cpu-stress-template.json`：备选方案,CPU 压力注入,需实例装 SSM Agent 且有 SSM 权限。
- `scripts/11-run-fis.sh`：本地跑,建 FIS 角色并启动实验(默认引用 CPU 模板,可改为停实例模板)。
- `scripts/11-collect.sh`：实例上跑,分 before/during/after 三阶段采 SLI。

## 重要:IAM 权限依赖(开机前确认)

现有 terraform 的实例默认没有 IAM instance profile。三篇对权限的需求:

- 06 上报指标:`06-report-error-rate.sh` 在实例上调用 `cloudwatch:PutMetricData`。
  - 方案A(推荐):给实例加一个带 CloudWatchAgentServerPolicy(或仅 PutMetricData)的 instance profile。
  - 方案B(最省事):把上报脚本改到本地跑(本地有 CloudWatch 权限),对着公网 app_url 压测并上报,不需要改实例权限。
- 11 FIS 停实例方案:只需 FIS 执行角色能 stop/start EC2,不需要实例装 SSM。首选此方案。
- 11 FIS CPU 压力方案:需要实例装 SSM Agent 并有 SSM 权限,较麻烦,作为备选。
- 10 金丝雀:纯在实例内两端口分流对比,不需要任何额外云端权限,零配置直接跑;若想演示生产级 ALB 加权则另需 ELB 权限(可选)。

结论:想最省事,06 用方案B(本地上报)、11 用停实例模板,就都不用改动实例的 IAM。

## FIS 两方案怎么选

- 优先用 `fis-stop-instance-template.json`(停实例):最经典的混沌动作,无 SSM 依赖,直接能跑,演示"实例挂了系统怎样、恢复多久"。
- 若想演示"负载压力下的降级"再用 CPU 压力模板,但要先给实例配 SSM。
- 用停实例模板时,把 `11-run-fis.sh` 里引用的模板文件名改成 `fis-stop-instance-template.json` 即可。

## 清理

实验完成后除了 terraform destroy,还要清理手工创建的:SNS 主题、CloudWatch 告警、FIS 实验模板、FIS 角色、(若建了)ALB 及目标组。runbook 阶段四有对应命令。
