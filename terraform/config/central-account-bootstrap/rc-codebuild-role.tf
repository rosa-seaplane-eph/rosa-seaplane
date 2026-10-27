# Shared IAM role for Regional Cluster CodeBuild projects
#
# This role is used by SDK-created RC CodeBuild projects (one per region).
# The role name is referenced by ARN in the SDK provisioner script.

data "aws_caller_identity" "rc_shared" {}

locals {
  zoa_central_deployments_ssm_parameter_arns = [
    for region in distinct([
      var.zoa_central_deployments_primary_region,
      var.zoa_central_deployments_replica_region,
    ]) : "arn:aws:ssm:${region}:${data.aws_caller_identity.rc_shared.account_id}:parameter/zoa/deployments/*"
  ]
}

resource "aws_iam_role" "rc_codebuild_role" {
  name = "${local.iam_role_prefix}rc-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "rc_codebuild_policy" {
  role = aws_iam_role.rc_codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup"]
        Resource = [
          for group in local.regional_log_groups :
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.rc_shared.account_id}:log-group:${group}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          for group in local.regional_log_groups :
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.rc_shared.account_id}:log-group:${group}:*"
        ]
      },
      {
        Sid    = "PipelineArtifactRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.codepipeline_shared.artifact_bucket_arn,
          "${module.codepipeline_shared.artifact_bucket_arn}/*"
        ]
      },
      {
        Sid    = "PipelineArtifactEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = module.codepipeline_shared.artifact_kms_key_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:${data.aws_caller_identity.rc_shared.account_id}:parameter/infra/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource",
          "ssm:ListTagsForResource",
        ]
        Resource = local.zoa_central_deployments_ssm_parameter_arns
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        # Match upstream/main: RC Terraform's central provider needs DNS access.
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = "*"
      }
      ], var.regional_cluster == null ? [] : [
      {
        Sid      = "RegionalTerraformStateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.regional_state_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "regional-cluster/${var.regional_cluster.regional_id}.tfstate",
              "regional-cluster/${var.regional_cluster.regional_id}.tfstate.tflock"
            ]
          }
        }
      },
      {
        Sid      = "RegionalTerraformStateBucketRead"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = local.regional_state_bucket_arn
      },
      {
        Sid    = "RegionalTerraformStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = local.regional_state_object_arns
      }
      ], length(local.regional_assume_role_arns) > 0 ? [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.regional_assume_role_arns
      }
      ] : [], local.regional_same_account ? [
      # Preserve the upstream RC provisioning permissions for deployments where
      # TARGET_ACCOUNT_ID is the central account and no child role is assumed.
      {
        Sid    = "RegionalServiceProvisioning"
        Effect = "Allow"
        Action = [
          "logs:*",
          "ec2:*",
          "eks:*",
          "ecs:*",
          "kms:*",
          "apigateway:*",
          "iot:*",
          "rds:*",
          "elasticache:*",
          "secretsmanager:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "cloudwatch:*",
          "acm:*",
          "tag:*",
          "lambda:*",
          "sqs:*",
          "scheduler:*",
          "dynamodb:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "RegionalIAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = local.regional_iam_role_arns
      },
      {
        Sid    = "RegionalIAMManagedPolicyAttachments"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = concat(local.regional_iam_role_arns, local.regional_managed_iam_policy_arns)
      },
      {
        Sid    = "RegionalIAMManagedPolicyRead"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion"
        ]
        Resource = local.regional_managed_iam_policy_arns
      },
      {
        Sid      = "RegionalIAMPassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = local.regional_iam_role_arns
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "apigateway.amazonaws.com",
              "cloudtrail.amazonaws.com",
              "ecs-tasks.amazonaws.com",
              "events.amazonaws.com",
              "eks.amazonaws.com",
              "lambda.amazonaws.com",
              "logs.amazonaws.com",
              "logs.${var.region}.amazonaws.com",
              "monitoring.rds.amazonaws.com",
              "pods.eks.amazonaws.com",
              "scheduler.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid    = "RegionalIAMInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
          "iam:ListInstanceProfileTags"
        ]
        Resource = local.regional_iam_instance_profile_arns
      },
      {
        Sid    = "RegionalIAMInstanceProfileRoles"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = concat(local.regional_iam_role_arns, local.regional_iam_instance_profile_arns)
      },
      {
        Sid      = "RegionalIAMServiceLinkedRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "autoscaling.amazonaws.com",
              "elasticache.amazonaws.com",
              "elasticloadbalancing.amazonaws.com",
              "eks.amazonaws.com",
              "ecs.amazonaws.com",
              "rds.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid      = "RegionalS3Resources"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = concat(local.regional_s3_bucket_arns, local.regional_s3_object_arns)
      }
    ] : [])
  })
}
