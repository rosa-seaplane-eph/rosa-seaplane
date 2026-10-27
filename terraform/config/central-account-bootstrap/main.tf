provider "aws" {
  region = var.region
}

# Existing states hold the retired public platform-image ECR repository, created
# through this alias (ECR Public is us-east-1 only). Terraform needs the alias to
# destroy it; remove once every environment has applied without that resource.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Existing states hold the retired build-platform-image resources, created
# through the module's own provider configuration. The provider-only module
# lets Terraform destroy them; remove it with the alias above.
module "platform_image_builder" {
  source = "../../modules/platform-image-builder"

  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  # When name_prefix is set (e.g., "eph-199b4083"), shared resource names are prefixed with "eph-199b4083-".
  name_prefix = var.name_prefix != "" ? "${var.name_prefix}-" : ""

  # IAM role prefix is separately configurable. Defaults to name_prefix for backward compatibility.
  # Ephemeral: "eph-{id}-" → roles like "eph-199b4083-rc-codebuild-role"
  # Standing: "" → unprefixed roles like "rc-codebuild-role"
  # Can be overridden via iam_role_prefix variable (e.g., "int-" for integration)
  iam_role_prefix = var.iam_role_prefix != null ? (var.iam_role_prefix != "" ? "${var.iam_role_prefix}-" : "") : local.name_prefix

  regional_assume_role_arns = var.regional_cluster == null ? [] : [
    "arn:${data.aws_partition.current.partition}:iam::${var.regional_cluster.account_id}:role/${var.regional_cluster.child_admin_role_name}"
  ]
  # MC provisioning also reads state and updates discovery records in the RC account.
  management_assume_role_arns = distinct(concat(local.regional_assume_role_arns, [
    for cluster in var.management_clusters :
    "arn:${data.aws_partition.current.partition}:iam::${cluster.account_id}:role/${cluster.child_admin_role_name}"
  ]))
  regional_same_account = var.regional_cluster == null ? false : var.regional_cluster.account_id == data.aws_caller_identity.current.account_id
  management_same_account = local.regional_same_account || contains(
    [for cluster in var.management_clusters : cluster.account_id], data.aws_caller_identity.current.account_id
  )
  cluster_log_group_prefix = "/aws/codebuild/${basename(module.codepipeline_shared.pipeline_role_arn)}"
  regional_project_names   = var.regional_cluster == null ? [] : [var.regional_cluster.project_name]
  management_project_names = [for cluster in var.management_clusters : cluster.project_name]
  cluster_project_names    = concat(local.regional_project_names, local.management_project_names)
  # RC/MC CodeBuild projects pull the platform image from another account's ECR
  # with their service role, which needs pull access to its repository.
  platform_image_pattern         = "^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com/([^:@]+)"
  platform_image_repository_arns = [
    for parts in try([regex(local.platform_image_pattern, var.platform_image)], []) :
    "arn:${data.aws_partition.current.partition}:ecr:${parts[1]}:${parts[0]}:repository/${parts[2]}"
  ]
  platform_image_pull_statements = flatten([
    for repository_arn in local.platform_image_repository_arns : [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = repository_arn
      }
    ]
  ])
  # Existing builds keep their original project log groups until the SDK
  # reconciles projects to the shared groups used by future cluster names.
  regional_log_groups = concat(["${local.cluster_log_group_prefix}/regional"], [
    for project in local.regional_project_names : "/aws/codebuild/${project}"
  ])
  management_log_groups = concat(["${local.cluster_log_group_prefix}/management"], [
    for project in local.management_project_names : "/aws/codebuild/${project}"
  ])
}

# Shared GitHub CodeStar Connection
# The bootstrap script ensures the shared connection exists and imports it here
# so Terraform can reference the selected ARN without deleting it on teardown.
# During teardown, `terraform state rm` removes it before destroy so the
# connection persists across CI runs.
resource "aws_codestarconnections_connection" "github" {
  name          = "rosa-regional-github-shared"
  provider_type = "GitHub"

  lifecycle {
    prevent_destroy = true
  }
}

module "codepipeline_shared" {
  source = "../../modules/codepipeline-shared"

  github_connection_arn = aws_codestarconnections_connection.github.arn
  name_prefix           = var.name_prefix
  region                = var.region
  cluster_project_names = local.cluster_project_names
}

# CodeBuild Failure Notifications
# Gated by an explicit feature flag (see var.enable_slack_notifications).
# Monitors the RC/MC CodeBuild projects rendered at bootstrap time; rerun
# bootstrap to include clusters added later.
module "codebuild_notifications" {
  source = "../../modules/codebuild-notifications"
  count  = var.enable_slack_notifications && length(local.cluster_project_names) > 0 ? 1 : 0

  slack_webhook_ssm_param = var.slack_webhook_ssm_param
  name_prefix             = var.name_prefix
  project_names           = local.cluster_project_names
}
