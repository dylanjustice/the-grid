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
