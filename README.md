# sre-aws-lab

《老计聊SRE》系列的配套实验环境。一台 AWS t3.micro 上跑一个极简 FastAPI 服务,作为 SRE 各个概念(SLI、SLO、错误预算、告警、复盘、容量等)的统一实验对象。文章里的每一个数字,都来自对这个服务的真实压测。

> 配套技术专栏：老计聊SRE(CSDN)。这个仓库是"教具",讲透 SRE 方法论才是主线。

## 设计理念

- **同一个实验对象**：整个系列围绕这一个示例应用展开,读者能看到同一个系统的可靠性怎么被一步步建立起来。
- **真实数据说话**：不编造数字。文章里的可用性、延迟分位、错误率等,都是脚本对真实服务压测跑出来的。
- **可控故障**：应用内置可调的延迟和错误率端点,方便演示各种"服务变差"的场景。
- **低成本可复现**：t3.micro 基本在免费额度内,用完 `terraform destroy` 即清理。

## 目录结构

```text
sre-aws-lab/
  app/
    main.py                          FastAPI 示例应用(v1 正常版)
    main_v2.py                       坏版本(第10篇金丝雀用,/work 按概率500)
    requirements.txt
  scripts/
    measure-sli.sh                   发混合流量,算可用性/错误率/延迟分位
    collect-sli-dataset.sh           采集第一批 SLI 数据
    collect-sli-dataset2.sh          采集第二批(三档健康度等)
    06-create-alarm.sh               建 SNS + 基于错误率的 CloudWatch 告警
    06-report-error-rate.sh          上报错误率到 CloudWatch 自定义指标
    10-start-two-versions.sh         并行启动 v1(8000) 和 v2(8001)
    10-canary-compare.sh             对比 v1/v2 的错误率(金丝雀)
    11-run-fis.sh                    建 FIS 角色并启动混沌实验
    11-collect.sh                    混沌实验 before/during/after 三段采 SLI
  fis/
    fis-trust-policy.json            FIS 执行角色信任策略
    fis-stop-instance-template.json  FIS 停实例模板(首选,无 SSM 依赖)
    fis-cpu-stress-template.json     FIS CPU 压力模板(备选,需 SSM)
  terraform/
    main.tf                          t3.micro + 安全组 + 开机部署应用
    variables.tf
    outputs.tf
    terraform.tfvars.example
    .gitignore
  experiment-run-log.md              完整实验记录与采集到的原始数据
```

## 示例应用端点

| 端点 | 用途 |
|------|------|
| `GET /` | 服务基本信息 |
| `GET /health` | 健康检查 |
| `GET /work` | 正常业务端点 |
| `GET /slow?ms=500` | 可控延迟,演示延迟类 SLI |
| `GET /flaky?rate=0.3` | 可控错误率,演示错误率 SLI / 错误预算 / 告警 |

`/slow` 和 `/flaky` 是为教学演示故意做的可控端点,不是生产做法。

## 文章与实验的对应关系

| 篇号 | 主题 | 用到的实验 / 数据 |
|------|------|------------------|
| 01 | SRE 是什么 | 用本仓库的示例应用作为全系列实验对象 |
| 02 | SLI | `measure-sli.sh` 压测:可用性 96.40%、平均延迟 39ms 但 P95 达 302ms |
| 03 | SLO | 三档健康度数据:可用性 99.60% / 97.80% / 93.80%,对照 SLO 判定达标与违约 |
| 04 | 错误预算 | 稳态错误率基线 0.10%(数据已采) |
| 05 / 07 | 告警 / 复盘 | 故障时间线:正常 0.33% 到 故障 12% 再到 恢复 0% |
| 08 | 健康检查 | 自愈验证:systemd `Restart=always`,MTTR < 1s |
| 09 | 容量 | 过载拐点:吞吐平台约 185 req/s |

原始数据与采集过程见 [`experiment-run-log.md`](experiment-run-log.md)。

## 快速上手

前置:已安装 Terraform、配好 AWS 凭证、有一台可用的 AWS 账号。

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # 填入你的公网IP(用于放行SSH和应用端口)
terraform init
terraform plan
terraform apply
```

apply 完成后,输出里的 `app_url` 就是示例应用地址,本地浏览器打开即可访问。

跑一次 SLI 压测:

```bash
BASE_URL=<app_url> bash scripts/measure-sli.sh
```

SSH 登录(排查用):`ssh ubuntu@<public_ip>`。开机脚本部署完成的标志是文件 `/var/log/sre-demo-userdata-done` 存在。

用完清理:

```bash
cd terraform
terraform destroy
```

## 安全说明

- SSH 端口(22)只放行你指定的 IP;应用端口(8000)只放行能开浏览器的本地 IP。均不对全网开放。
- `terraform.tfvars`(含个人 IP)、`terraform.tfstate`、`.terraform/` 均已在 `.gitignore` 中排除,不会进仓库。本仓库不含任何真实 IP、密钥或账号信息。

## 成本

- t3.micro 在 AWS 免费额度内(每月 750 小时);超出后约 $0.0104/小时。
- 系列做完可 `terraform destroy` 释放;成本极低,也可长期保留。

## License

MIT
