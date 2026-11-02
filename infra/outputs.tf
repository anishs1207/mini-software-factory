output "public_ip" { value = data.oci_core_vnic.briefing.public_ip_address }
output "product_url" {
  description = "Intended Daily Briefing product URL after the product is deployed on HTTP port 80; never an agent dashboard."
  value       = "http://${data.oci_core_vnic.briefing.public_ip_address}"
}
output "ssh_command" { value = "ssh ubuntu@${data.oci_core_vnic.briefing.public_ip_address}" }
output "dashboard_tunnel" {
  description = "Private SSH tunnel for the localhost-only OpenClaw and optional Hermes dashboards."
  value       = "ssh -L 18789:127.0.0.1:18789 -L 9119:127.0.0.1:9119 ubuntu@${data.oci_core_vnic.briefing.public_ip_address}"
}
