data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "briefing" {
  depends_on          = [terraform_data.bootstrap_preflight]
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = "briefing-agent-vm"
  shape               = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gb
  }
  source_details {
    source_type = "image"
    source_id   = var.image_id != null ? var.image_id : data.oci_core_images.ubuntu.images[0].id
  }
  create_vnic_details {
    subnet_id        = var.subnet_id != null ? var.subnet_id : oci_core_subnet.briefing[0].id
    assign_public_ip = true
  }
  metadata = {
    ssh_authorized_keys = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }
}

data "oci_core_vnic_attachments" "briefing" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.briefing.id
}

data "oci_core_vnic" "briefing" {
  vnic_id = data.oci_core_vnic_attachments.briefing.vnic_attachments[0].vnic_id
}
