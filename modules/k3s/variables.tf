variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "tailscale_enabled" {
  type    = bool
  default = false
}

variable "tailscale_advertise_routes" {
  type    = string
  default = ""
}
