output "artifact_bucket_name" {
  description = "S3 bucket used by per-cluster CodePipelines."
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the per-cluster CodePipeline artifact bucket."
  value       = aws_s3_bucket.artifacts.arn
}

output "artifact_kms_key_arn" {
  description = "KMS key ARN used to encrypt per-cluster CodePipeline artifacts."
  value       = aws_kms_key.artifacts.arn
}

output "pipeline_role_arn" {
  description = "IAM role assumed by per-cluster CodePipelines."
  value       = aws_iam_role.pipeline.arn
}
