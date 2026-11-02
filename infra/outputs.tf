output "public_ip" { value = data.oci_core_vnic.briefing.public_ip_address }
output "ssh_command" { value = "ssh ubuntu@${data.oci_core_vnic.briefing.public_ip_address}" }
output "dashboard_tunnel" { value = "ssh -L 18789:127.0.0.1:18789 ubuntu@${data.oci_core_vnic.briefing.public_ip_address}" }
