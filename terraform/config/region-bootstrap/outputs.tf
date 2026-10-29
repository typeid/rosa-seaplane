output "github_connection_arn" {
  description = "ARN of the GitHub connection in the RC account"
  value       = aws_codestarconnections_connection.github.arn
}

output "codebuild_role_arn" {
  description = "IAM role used by the RC and MC CodeBuild projects. MC accounts' child admin roles must trust it."
  value       = module.codepipeline_shared.codebuild_role_arn
}

output "codepipeline_role_arn" {
  description = "IAM role used by the RC and MC CodePipelines"
  value       = module.codepipeline_shared.pipeline_role_arn
}

output "codepipeline_artifact_bucket_name" {
  description = "S3 bucket used by the RC and MC CodePipelines"
  value       = module.codepipeline_shared.artifact_bucket_name
}
