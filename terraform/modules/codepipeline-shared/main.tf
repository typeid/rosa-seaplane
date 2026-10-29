data "aws_caller_identity" "current" {}

locals {
  name_prefix         = var.name_prefix != "" ? "${var.name_prefix}-" : ""
  account_id          = data.aws_caller_identity.current.account_id
  rc_state_bucket_arn = "arn:aws:s3:::terraform-state-${data.aws_caller_identity.current.account_id}-${var.region}"
  codebuild_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })

  common_tags = {
    function  = "cluster-provisioning"
    module    = "codepipeline-shared"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}cluster-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-pipeline-artifacts"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "pipeline" {
  name = "${local.name_prefix}cluster-codepipeline-role"
  tags = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "ArtifactBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Sid    = "ArtifactObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "GitHubConnection"
        Effect   = "Allow"
        Action   = "codestar-connections:UseConnection"
        Resource = var.github_connection_arn
      },
      {
        Sid    = "ClusterCodeBuild"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        Resource = [
          "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ProvisioningScope" = aws_iam_role.pipeline.arn
          }
        }
      }
      ], length(var.cluster_project_names) > 0 ? [
      {
        Sid    = "ConfiguredClusterCodeBuild"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild"
        ]
        Resource = [
          for project in var.cluster_project_names :
          "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/${project}"
        ]
      }
    ] : [])
  })
}

# CodeBuild roles. RC projects apply the RC Terraform in this account. MC
# projects only manage their RC-side resources here and apply MC infrastructure
# after assuming the child admin role in the MC account, whose trust policy
# names the MC role. RC builds cannot reach MC accounts.

resource "aws_iam_role" "rc_codebuild" {
  name = "${local.name_prefix}rc-codebuild-role"
  tags = local.common_tags

  assume_role_policy = local.codebuild_assume_role_policy
}

# Same effective access the RC build had through the child admin role.
resource "aws_iam_role_policy_attachment" "rc_codebuild_admin" {
  role       = aws_iam_role.rc_codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "rc_codebuild_same_account" {
  role = aws_iam_role.rc_codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid         = "NoRolesOutsideThisAccount"
      Effect      = "Deny"
      Action      = "sts:AssumeRole"
      NotResource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
    }]
  })
}

resource "aws_iam_role" "mc_codebuild" {
  name = "${local.name_prefix}mc-codebuild-role"
  tags = local.common_tags

  assume_role_policy = local.codebuild_assume_role_policy
}

resource "aws_iam_role_policy" "mc_codebuild" {
  role = aws_iam_role.mc_codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "BuildLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/codebuild/${aws_iam_role.pipeline.name}/management",
          "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/codebuild/${aws_iam_role.pipeline.name}/management:*",
        ]
      },
      {
        Sid      = "PipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        # Read RC outputs; write only the RC-side MC states.
        Sid      = "RCStateRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [local.rc_state_bucket_arn, "${local.rc_state_bucket_arn}/*"]
      },
      {
        Sid    = "RCSideMCStateWrite"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${local.rc_state_bucket_arn}/kube-applier-dynamodb/*",
          "${local.rc_state_bucket_arn}/mc-zoa-target-ssm/*",
        ]
      },
      {
        # Account IDs the build resolves from /infra/* references.
        Sid      = "InfraParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/infra/*"
      },
      {
        Sid    = "KubeApplierTables"
        Effect = "Allow"
        Action = ["dynamodb:*"]
        Resource = [
          "arn:aws:dynamodb:${var.region}:${local.account_id}:table/*-specs-*",
          "arn:aws:dynamodb:${var.region}:${local.account_id}:table/*-status-*",
        ]
      },
      {
        Sid      = "SeaplaneOperatorTableAccess"
        Effect   = "Allow"
        Action   = ["iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies"]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.regional_id}-seaplane-operator"
      },
      {
        Sid    = "ZoaTargetRows"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter",
          "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource",
        ]
        Resource = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/zoa/targets/*"
      },
      {
        # Terraform reads parameter metadata through DescribeParameters, which
        # has no resource-level scoping.
        Sid      = "DescribeParameters"
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        # MC accounts' child admin roles; their trust policies name this role.
        Sid      = "MCAccounts"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [for name in var.mc_admin_role_names : "arn:aws:iam::*:role/${name}"]
      },
      ], var.platform_image_repository_arn == null ? [] : [
      {
        Sid      = "PlatformImageAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "PlatformImagePull"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = var.platform_image_repository_arn
      },
    ])
  })
}
