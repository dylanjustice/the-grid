output "instance_id" {
  value = aws_instance.k3s.id
}

output "role_id" {
  value = aws_iam_role.k3s.id
}
