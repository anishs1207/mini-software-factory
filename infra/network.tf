data "aws_ec2_instance_type_offerings" "briefing" {
  filter {
    name   = "instance-type"
    values = ["m7i-flex.large"]
  }
  location_type = "availability-zone"
}

resource "aws_vpc" "briefing" {
  depends_on           = [terraform_data.bootstrap_preflight]
  cidr_block           = "10.77.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "briefing-vpc" }
}

resource "aws_internet_gateway" "briefing" {
  vpc_id = aws_vpc.briefing.id
  tags   = { Name = "briefing-internet-gateway" }
}

resource "aws_subnet" "briefing" {
  vpc_id                  = aws_vpc.briefing.id
  cidr_block              = "10.77.1.0/24"
  availability_zone       = sort(data.aws_ec2_instance_type_offerings.briefing.locations)[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "briefing-public-subnet" }
}

resource "aws_route_table" "briefing" {
  vpc_id = aws_vpc.briefing.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.briefing.id
  }
  tags = { Name = "briefing-public-route" }
}

resource "aws_route_table_association" "briefing" {
  subnet_id      = aws_subnet.briefing.id
  route_table_id = aws_route_table.briefing.id
}

resource "aws_security_group" "briefing" {
  name_prefix = "briefing-public-"
  description = "SSH from the operator; HTTP and HTTPS for the product"
  vpc_id      = aws_vpc.briefing.id
  tags        = { Name = "briefing-public-security" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.briefing.id
  cidr_ipv4         = data.external.local_prereqs.result.ssh_allowed_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.briefing.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.briefing.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.briefing.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
