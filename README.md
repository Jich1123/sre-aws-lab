# 老计聊SRE 实验环境

贯穿《老计聊SRE》全系列的示例应用和基础设施。一台 t3.micro 上跑一个极简 FastAPI 服务,作为 SRE 各概念(SLI/SLO/告警/复盘等)的实验对象。

## 目录

```text
sre-aws-lab/
├── app/
│   ├── main.py            FastAPI 示例应用
│   └── requirements.txt
├── scripts/               SLI 压测与数据采集脚本
└── terraform/
    ├── main.tf            t3.micro + 安全组 + 开机部署应用
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── .gitignore
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

## 使用

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # 填入你的IP
terraform init
terraform plan
terraform apply
```

输出里有 `app_url`,在本地浏览器打开即可访问示例应用。

SSH(从跳板机):`ssh ubuntu@<public_ip>`,开机脚本部署完成的标志是 `/var/log/sre-demo-userdata-done`。

## 安全说明

- SSH 端口(22)只放行跳板机和本地 IP;应用端口(8000)只放行能开浏览器的本地 IP。均不对全网开放。
- `terraform.tfvars`(含个人IP)、`terraform.tfstate` 已在 `.gitignore` 中排除,不提交。

## 成本

- t3.micro 在 AWS 免费额度内(每月750小时);超出后约 $0.0104/小时。
- 系列做完可 `terraform destroy` 释放;成本极低也可长期保留。
