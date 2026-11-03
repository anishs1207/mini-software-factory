data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "briefing" {
  key_name_prefix = "briefing-agent-"
  public_key      = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "aws_instance" "briefing" {
  depends_on                  = [terraform_data.bootstrap_preflight, aws_route_table_association.briefing, aws_vpc_security_group_ingress_rule.ssh, aws_vpc_security_group_egress_rule.all_ipv4]
  ami                         = coalesce(var.ami_id, data.aws_ssm_parameter.ubuntu_2404.value)
  instance_type               = "m7i-flex.large"
  subnet_id                   = aws_subnet.briefing.id
  vpc_security_group_ids      = [aws_security_group.briefing.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.briefing.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = { Name = "briefing-agent-vm" }
}
