output "aws_account_id" {
  description = "AWS account selected by aws_profile for this Terraform run."
  value       = data.aws_caller_identity.current.account_id
}
output "public_ip" { value = aws_instance.briefing.public_ip }
output "ssh_private_key_path" {
  description = "Local private key file path for the operator SSH command."
  value       = pathexpand(var.ssh_private_key_path)
}
output "product_url" {
  description = "Intended product HTTP URL after the builder deploys it."
  value       = "http://${aws_instance.briefing.public_ip}"
}
output "ssh_command" { value = "ssh -i ${pathexpand(var.ssh_private_key_path)} ubuntu@${aws_instance.briefing.public_ip}" }
output "manager_chat_command" {
  description = "Interactive manager CLI after bootstrap; exit the chat to let the issue poller resume."
  value       = "ssh -t -i ${pathexpand(var.ssh_private_key_path)} ubuntu@${aws_instance.briefing.public_ip} 'cd ~/briefing-repo && bash agents/manager-chat.sh'"
}
output "dashboard_tunnel" {
  description = "Private SSH tunnel for localhost-only agent dashboards."
  value       = "ssh -i ${pathexpand(var.ssh_private_key_path)} -L 18789:127.0.0.1:18789 -L 9119:127.0.0.1:9119 ubuntu@${aws_instance.briefing.public_ip}"
}
