variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "subnet_id" {
  type = string
}

variable "allowed_ingress_ranges" {
  type    = set(string)
  default = []
}

variable "vpc_id" {
  type = string
}
