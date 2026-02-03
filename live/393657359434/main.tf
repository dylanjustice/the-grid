provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "the-grid"
      Terraform = true
      Class     = "${path.module}"
    }
  }
}

data "aws_availability_zones" "available" {
  region = var.region
}

resource "random_string" "vpc_suffix" {
  length  = 4
  upper   = false
  lower   = true
  numeric = true
  special = false
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "thegrid-${random_string.vpc_suffix.result}"
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

}

output "azs" {
  value = data.aws_availability_zones.available.names
}
