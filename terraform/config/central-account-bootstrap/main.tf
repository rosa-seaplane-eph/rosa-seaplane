provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  # When name_prefix is set (e.g., "eph-199b4083"), resource names become "eph-199b4083-build-platform-image", etc.
  name_prefix = var.name_prefix != "" ? "${var.name_prefix}-" : ""

  # IAM role prefix is separately configurable. Defaults to name_prefix for backward compatibility.
  # Ephemeral: "eph-{id}-" → roles like "eph-199b4083-rc-codebuild-role"
  # Standing: "" → unprefixed roles like "rc-codebuild-role"
  # Can be overridden via iam_role_prefix variable (e.g., "int-" for integration)
  iam_role_prefix = var.iam_role_prefix != null ? (var.iam_role_prefix != "" ? "${var.iam_role_prefix}-" : "") : local.name_prefix

  regional_assume_role_arns = var.regional_cluster == null ? [] : [
    "arn:${data.aws_partition.current.partition}:iam::${var.regional_cluster.account_id}:role/${var.regional_cluster.child_admin_role_name}"
  ]
  regional_iam_role_arns = var.regional_cluster == null ? [] : [
    "arn:${data.aws_partition.current.partition}:iam::${var.regional_cluster.account_id}:role/${var.regional_cluster.regional_id}-*"
  ]
  regional_iam_instance_profile_arns = var.regional_cluster == null ? [] : [
    "arn:${data.aws_partition.current.partition}:iam::${var.regional_cluster.account_id}:instance-profile/${var.regional_cluster.regional_id}-*"
  ]
  regional_state_bucket_arn = var.regional_cluster == null ? "" : "arn:${data.aws_partition.current.partition}:s3:::terraform-state-${var.regional_cluster.account_id}-${var.regional_cluster.region}"
  regional_state_object_arns = var.regional_cluster == null ? [] : [
    "${local.regional_state_bucket_arn}/regional-cluster/${var.regional_cluster.regional_id}.tfstate",
    "${local.regional_state_bucket_arn}/regional-cluster/${var.regional_cluster.regional_id}.tfstate.tflock"
  ]
  regional_s3_bucket_arns = var.regional_cluster == null ? [] : [
    for bucket in [
      "${var.regional_cluster.regional_id}-cloudtrail-${var.regional_cluster.account_id}",
      "${var.regional_cluster.regional_id}-loki-logs-${var.regional_cluster.account_id}",
      "${var.regional_cluster.regional_id}-thanos-metrics-${var.regional_cluster.account_id}",
      "${var.regional_cluster.regional_id}-zoa-outputs-${var.regional_cluster.account_id}",
      "${var.regional_cluster.regional_id}-sre-alb-logs-${var.regional_cluster.account_id}",
      "hypershift-${var.regional_cluster.regional_id}-oidc-${var.regional_cluster.account_id}"
    ] : "arn:${data.aws_partition.current.partition}:s3:::${bucket}"
  ]
  regional_s3_object_arns = [for bucket_arn in local.regional_s3_bucket_arns : "${bucket_arn}/*"]
  regional_managed_iam_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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

# Platform Image ECR Repository
module "platform_image" {
  source = "../../modules/platform-image"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  resource_name_base = "rosa-regional"
  name_prefix        = var.name_prefix
  tags = {
    Name        = "rosa-seaplane-image"
    Environment = var.environment
  }
}

module "codepipeline_shared" {
  source = "../../modules/codepipeline-shared"

  github_connection_arn = aws_codestarconnections_connection.github.arn
  name_prefix           = var.name_prefix
  region                = var.region
  cluster_project_names = concat(local.regional_project_names, local.management_project_names)
}

module "platform_image_builder" {
  source = "../../modules/platform-image-builder"

  github_repository     = var.github_repository
  region                = var.region
  github_connection_arn = aws_codestarconnections_connection.github.arn
  platform_ecr_repo     = module.platform_image.ecr_repository_url
  platform_ecr_repo_arn = module.platform_image.ecr_repository_arn
  name_prefix           = var.name_prefix
}

# CodeBuild Failure Notifications
# Gated by an explicit feature flag (see var.enable_slack_notifications).
# Currently only monitors the build-platform-image project.
# RC/MC notifications are SDK-side (out of scope for this module).
module "codebuild_notifications" {
  source = "../../modules/codebuild-notifications"
  count  = var.enable_slack_notifications ? 1 : 0

  slack_webhook_ssm_param = var.slack_webhook_ssm_param
  name_prefix             = var.name_prefix
  project_names           = [module.platform_image_builder.build_platform_image_project_name]
}
