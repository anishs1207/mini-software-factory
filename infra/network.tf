# The default network contains one public subnet, no load balancer, and no DB.
# Supply subnet_id to reuse an existing public subnet instead.
resource "oci_core_vcn" "briefing" {
  count          = var.subnet_id == null ? 1 : 0
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.77.0.0/16"]
  dns_label      = "briefing"
  display_name   = "briefing-vcn"

  lifecycle {
    precondition {
      condition     = var.ssh_allowed_cidr != null
      error_message = "Set ssh_allowed_cidr to your public IP /32 before creating the default network."
    }
  }
}

resource "oci_core_internet_gateway" "briefing" {
  count          = var.subnet_id == null ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.briefing[0].id
  enabled        = true
  display_name   = "briefing-internet-gateway"
}

resource "oci_core_route_table" "briefing" {
  count          = var.subnet_id == null ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.briefing[0].id
  display_name   = "briefing-public-route"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.briefing[0].id
  }
}

resource "oci_core_security_list" "briefing" {
  count          = var.subnet_id == null ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.briefing[0].id
  display_name   = "briefing-public-security"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
  ingress_security_rules {
    description = "SSH from Terraform operator"
    source      = var.ssh_allowed_cidr
    protocol    = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }
  ingress_security_rules {
    description = "Public product HTTP"
    source      = "0.0.0.0/0"
    protocol    = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }
  ingress_security_rules {
    description = "Public product HTTPS"
    source      = "0.0.0.0/0"
    protocol    = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }
  ingress_security_rules {
    description = "Path MTU discovery"
    source      = "0.0.0.0/0"
    protocol    = "1"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "briefing" {
  count                      = var.subnet_id == null ? 1 : 0
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.briefing[0].id
  cidr_block                 = "10.77.1.0/24"
  display_name               = "briefing-public-subnet"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.briefing[0].id
  security_list_ids          = [oci_core_security_list.briefing[0].id]
  prohibit_public_ip_on_vnic = false
}
