terraform {
  backend "s3" {
    bucket       = "tf-state-the-grid-account-a-prod"
    key          = "${path.module}/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
