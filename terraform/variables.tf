# ============================================
# 变量定义 - 老计聊SRE 示例应用实验环境
# ============================================

variable "region" {
  description = "AWS区域"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "实例类型,t3.micro在免费额度内,够跑示例应用"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "根盘大小GB"
  type        = number
  default     = 20
}

variable "name_prefix" {
  description = "资源名前缀"
  type        = string
  default     = "laoji-sre-lab"
}

variable "project_tag" {
  description = "项目标签,便于成本归类和清理"
  type        = string
  default     = "laoji-sre-lab"
}

variable "ssh_public_key_path" {
  description = "本地SSH公钥路径,私钥不进仓库"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# SSH 来源:跳板机和本地电脑(都用于登录)
variable "allowed_ssh_cidrs" {
  description = "允许SSH的来源CIDR列表,必须是具体IP/32,禁止0.0.0.0/0"
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_ssh_cidrs, "0.0.0.0/0")
    error_message = "禁止对全网开放SSH,请填具体IP/32。"
  }
}

# Web 应用(8000)来源:能开浏览器的本地电脑IP
variable "allowed_web_cidrs" {
  description = "允许访问Web应用(8000端口)的来源CIDR列表,必须是具体IP/32"
  type        = list(string)

  validation {
    condition     = !contains(var.allowed_web_cidrs, "0.0.0.0/0")
    error_message = "禁止对全网开放Web端口,请填具体IP/32。"
  }
}

variable "app_port" {
  description = "示例应用监听端口"
  type        = number
  default     = 8000
}
