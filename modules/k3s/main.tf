data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "k3s" {
  name   = "k3s-sg"
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "k3s_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

resource "aws_security_group_rule" "k3s_ssh" {
  for_each          = var.allowed_ingress_ranges
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.k3s.id
}
resource "aws_security_group_rule" "k3s_kubectl" {
  for_each          = var.allowed_ingress_ranges
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.k3s.id
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.al2023_arm.id
  instance_type               = "t4g.medium"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = file("${path.module}/userdata.sh")

  tags = {
    Name = "k3s-node"
  }
}
