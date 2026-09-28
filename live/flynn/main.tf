data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  azs             = ["us-east-2a"]
  az_count        = length(local.azs)
  subnet_newbits  = var.subnet_prefix - var.vpc_cidr_prefix
  private_subnets = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)]
  public_subnets  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + local.az_count)]
  repositories    = toset(["flynn/playwright-synthetics", "flynn/synthetics-operator", "flynn/playwright-runner-js"])
}
module "alpha_vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "6.6.0"
  name               = "thegrid-alpha"
  cidr               = var.vpc_cidr
  azs                = local.azs
  private_subnets    = local.private_subnets
  public_subnets     = local.public_subnets
  enable_nat_gateway = true
  single_nat_gateway = true
}

module "k3s" {
  source     = "../../modules/k3s"
  subnet_id  = module.alpha_vpc.private_subnets[0]
  vpc_id     = module.alpha_vpc.vpc_id
  region     = var.region
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_security_group" "vpc_endpoints" {
  name   = "vpc-endpoints-sg"
  vpc_id = module.alpha_vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset([
    "com.amazonaws.${var.region}.ssm",
    "com.amazonaws.${var.region}.ssmmessages",
    "com.amazonaws.${var.region}.ec2messages",
  ])

  vpc_id              = module.alpha_vpc.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.alpha_vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

module "ecr" {
  for_each        = local.repositories
  source          = "../../modules/ecr"
  repository_name = each.key
}


resource "aws_s3_bucket" "artifacts" {
  bucket = "${data.aws_caller_identity.current.account_id}-${var.region}-artifacts"
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "glacier-transition"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "k3s_s3_artifacts" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.artifacts.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "k3s_s3_artifacts" {
  name   = "k3s-s3-artifacts"
  role   = module.k3s.role_id
  policy = data.aws_iam_policy_document.k3s_s3_artifacts.json
}
