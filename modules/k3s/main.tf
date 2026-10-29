data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
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

resource "aws_security_group_rule" "k3s_tailscale" {
  type              = "ingress"
  from_port         = 41641
  to_port           = 41641
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s.id
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_secretsmanager_secret" "tailscale_auth_key" {
  count                   = var.tailscale_enabled ? 1 : 0
  name                    = "/the-grid/tailscale/auth-key"
  description             = "Tailscale auth key for the k3s EC2 subnet router"
  recovery_window_in_days = 0
}

resource "terraform_data" "k3s_user_data" {
  input = templatefile("${path.module}/userdata.sh", {
    tailscale_enabled    = var.tailscale_enabled
    tailscale_secret_arn = var.tailscale_enabled ? aws_secretsmanager_secret.tailscale_auth_key[0].arn : ""
    tailscale_routes     = var.tailscale_advertise_routes
  })
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

  user_data            = terraform_data.k3s_user_data.input
  iam_instance_profile = aws_iam_instance_profile.k3s.name
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "k3s-node-${random_string.suffix.result}"
  }
  lifecycle {
    # prevent_destroy = true # safeguard against accidental deletion of the k3s cluster
    replace_triggered_by = [
      terraform_data.k3s_user_data.output,
    ]
  }
}

data "aws_iam_policy_document" "k3s_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "k3s" {
  name               = "k3s-instance-role"
  assume_role_policy = data.aws_iam_policy_document.k3s_assume_role.json
}

resource "aws_iam_role_policy_attachment" "k3s_ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k3s" {
  name = "k3s-instance-profile"
  role = aws_iam_role.k3s.name
}

data "aws_iam_policy_document" "k3s_ecr_access" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "k3s_ecr_access" {
  name   = "k3s-ecr-access"
  role   = aws_iam_role.k3s.id
  policy = data.aws_iam_policy_document.k3s_ecr_access.json
}

data "aws_iam_policy_document" "k3s_tailscale_secrets" {
  count = var.tailscale_enabled ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.tailscale_auth_key[0].arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "k3s_tailscale_secrets" {
  count  = var.tailscale_enabled ? 1 : 0
  name   = "k3s-tailscale-secrets"
  role   = aws_iam_role.k3s.id
  policy = data.aws_iam_policy_document.k3s_tailscale_secrets[0].json
}
