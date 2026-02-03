provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "the-grid"
      Terraform = true
      Class     = "live/flynn"
    }
  }
}

data "aws_availability_zones" "available" {
  region = var.region
}


locals {
  azs             = data.aws_availability_zones.available.names
  az_count        = length(local.azs)
  subnet_newbits  = var.subnet_prefix - var.vpc_cidr_prefix
  private_subnets = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i)]
  public_subnets  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, local.subnet_newbits, i + local.az_count)]
}

module "alpha_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name               = "thegrid-alpha"
  cidr               = var.vpc_cidr
  azs                = local.azs
  private_subnets    = local.private_subnets
  public_subnets     = local.public_subnets
  enable_nat_gateway = true
}

