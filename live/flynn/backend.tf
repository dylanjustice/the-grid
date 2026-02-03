terraform {
  backend "s3" {
    bucket       = "the-grid-terraform-state"
    key          = "live/flynn/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
