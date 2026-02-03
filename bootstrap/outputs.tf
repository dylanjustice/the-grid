output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tf_state.arn
}

output "state_kms_key_arn" {
  value = aws_kms_key.tf_state.arn
}

