variable "repository_name" {
  description = "The name of the ECR repository to create."
  type        = string
}

resource "aws_ecr_repository" "flynn" {
  name                 = var.repository_name
  force_delete         = true
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

data "aws_iam_policy_document" "ecr" {
  statement {
    sid = "AllowOrgPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = ["o-gxfyx26q30"]
    }
  }
}


resource "aws_ecr_repository_policy" "flynn" {
  repository = var.repository_name
  policy     = data.aws_iam_policy_document.ecr.json
  depends_on = [aws_ecr_repository.flynn]
}
