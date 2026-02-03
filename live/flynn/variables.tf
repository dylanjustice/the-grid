variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "vpc_cidr_prefix" {
  description = "Numeric prefix length for vpc_cidr (must match vpc_cidr). Used to compute subnet sizes."
  type        = number
  default     = 20
}

variable "subnet_prefix" {
  description = "CIDR prefix for each subnet (e.g. 24 for /24 subnets)"
  type        = number
  default     = 24
}
