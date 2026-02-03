variable "region" {
  description = "AWS region for the bootstrap resources"
  type        = string
  default     = "us-east-2"
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state. Must be globally unique. Change this value before apply."
  type        = string
  default     = "the-grid-terraform-state"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = { Project = "the-grid" }
}
