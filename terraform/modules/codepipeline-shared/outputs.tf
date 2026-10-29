output "artifact_bucket_name" {
  description = "S3 bucket used by per-cluster CodePipelines."
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the per-cluster CodePipeline artifact bucket."
  value       = aws_s3_bucket.artifacts.arn
}

output "pipeline_role_arn" {
  description = "IAM role assumed by per-cluster CodePipelines."
  value       = aws_iam_role.pipeline.arn
}

output "rc_codebuild_role_arn" {
  description = "IAM role used by the RC CodeBuild project."
  value       = aws_iam_role.rc_codebuild.arn
}

output "mc_codebuild_role_arn" {
  description = "IAM role used by the MC CodeBuild projects. MC accounts' child admin roles must trust it."
  value       = aws_iam_role.mc_codebuild.arn
}
