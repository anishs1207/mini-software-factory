output "project_id" { value = var.project_id }
output "public_ip" { value = google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip }
output "ssh_private_key_path" {
  description = "Local private key file path for the operator SSH command."
  value       = data.external.local_prereqs.result.ssh_private_key_path
}
output "product_url" {
  description = "Public origin for an HTTP product on the configured product port, after deployment."
  value       = "http://${google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip}:${var.product_port}"
}
output "ssh_command" { value = "ssh -i ${data.external.local_prereqs.result.ssh_private_key_path} ubuntu@${google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip}" }
output "manager_chat_command" {
  description = "Interactive manager CLI after bootstrap."
  value       = "ssh -t -i ${data.external.local_prereqs.result.ssh_private_key_path} ubuntu@${google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip} 'cd ~/briefing-repo && bash agents/manager-chat.sh'"
}
output "dashboard_tunnel" {
  description = "Private SSH tunnel for agent dashboards."
  value       = "ssh -i ${data.external.local_prereqs.result.ssh_private_key_path} -L 18789:127.0.0.1:18789 -L 9119:127.0.0.1:9119 ubuntu@${google_compute_instance.briefing.network_interface[0].access_config[0].nat_ip}"
}
