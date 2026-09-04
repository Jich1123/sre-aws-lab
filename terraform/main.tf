# ============================================
# 老计聊SRE 示例应用实验环境:t3.micro + FastAPI
# 用途:部署贯穿全系列的示例HTTP服务,作为SRE概念的实验对象
#
# 核心流程:
#   terraform init
#   terraform plan
#   terraform apply
#   实验告一段落后可 terraform destroy(t3.micro成本极低,也可长期留着做系列)
#
# 成本:t3.micro 在AWS免费额度内(每月750小时),超出后约 $0.0104/小时
# ============================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

# 最新 Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================
# 安全组:SSH限跳板机+本地,Web端口8000限本地浏览器
# ============================================
resource "aws_security_group" "sre_lab" {
  name_prefix = "${var.name_prefix}-sg-"
  description = "SSH from allowed CIDRs, web app from browser CIDRs, all egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "FastAPI app"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.name_prefix}-sg"
    Project = var.project_tag
  }
}

resource "aws_key_pair" "sre_lab" {
  key_name_prefix = "${var.name_prefix}-key-"
  public_key      = file(var.ssh_public_key_path)

  tags = {
    Project = var.project_tag
  }
}

# ============================================
# 示例应用实例:开机自动部署FastAPI,用systemd托管
# ============================================
resource "aws_instance" "sre_lab" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.sre_lab.id]
  key_name               = aws_key_pair.sre_lab.key_name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # 开机部署示例应用。user_data 脚本顶格书写,避免 heredoc 缩进导致的失败。
  user_data = <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec > /var/log/sre-demo-deploy.log 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3-pip python3-venv

mkdir -p /opt/sre-demo
cat > /opt/sre-demo/main.py <<'PYEOF'
${file("${path.module}/../app/main.py")}
PYEOF

python3 -m venv /opt/sre-demo/venv
/opt/sre-demo/venv/bin/pip install --upgrade pip
/opt/sre-demo/venv/bin/pip install fastapi==0.115.6 "uvicorn[standard]==0.34.0"

cat > /etc/systemd/system/sre-demo.service <<'SVCEOF'
[Unit]
Description=laoji SRE demo app
After=network.target

[Service]
ExecStart=/opt/sre-demo/venv/bin/uvicorn main:app --host 0.0.0.0 --port ${var.app_port}
WorkingDirectory=/opt/sre-demo
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable sre-demo
systemctl start sre-demo
touch /var/log/sre-demo-userdata-done
EOF

  user_data_replace_on_change = true

  tags = {
    Name    = "${var.name_prefix}-instance"
    Project = var.project_tag
    Purpose = "laoji-sre-lab-demo-app"
  }
}
