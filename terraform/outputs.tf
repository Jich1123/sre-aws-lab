# ============================================
# 输出
# ============================================

output "instance_id" {
  value       = aws_instance.sre_lab.id
  description = "实例ID"
}

output "public_ip" {
  value       = aws_instance.sre_lab.public_ip
  description = "公网IP"
}

output "ssh_command" {
  value       = "ssh ubuntu@${aws_instance.sre_lab.public_ip}"
  description = "SSH连接命令(从跳板机执行)"
}

output "app_url" {
  value       = "http://${aws_instance.sre_lab.public_ip}:${var.app_port}"
  description = "示例应用访问地址(在本地浏览器打开)"
}

output "health_url" {
  value       = "http://${aws_instance.sre_lab.public_ip}:${var.app_port}/health"
  description = "健康检查地址"
}

output "destroy_reminder" {
  value       = "实验结束后运行 terraform destroy 释放实例,并确认EBS和安全组已清理。"
  description = "费用提醒"
}
