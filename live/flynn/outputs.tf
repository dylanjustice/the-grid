output "k3s_instance_id" {
  value = module.k3s.instance_id
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.id
}
