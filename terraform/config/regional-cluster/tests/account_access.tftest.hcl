mock_provider "aws" {
  override_during = plan
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}
mock_provider "aws" { alias = "central" }
mock_provider "aws" { alias = "dns_shard0" }
mock_provider "aws" { alias = "central_deployments" }
mock_provider "aws" { alias = "central_deployments_replica" }
mock_provider "pagerduty" {}
mock_provider "external" {}
mock_provider "random" {}
mock_provider "null" {}

override_module {
  target = module.regional_cluster
  outputs = {
    cluster_arn  = "arn:aws:eks:us-east-1:111111111111:cluster/test1234-regional"
    cluster_name = "test1234-regional"
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.platform_api
  values = {
    arn = "arn:aws:iam::111111111111:role/us-east-1-test1234-platform-api"
    id  = "us-east-1-test1234-platform-api"
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.installer_jump
  values = {
    arn = "arn:aws:iam::111111111111:role/us-east-1-test1234-installer-jump"
    id  = "us-east-1-test1234-installer-jump"
  }
}

variables {
  regional_id                   = "test1234-regional"
  environment                   = "ephemeral"
  region                        = "us-east-1"
  deployment_name               = "us-east-1-test1234"
  eph_prefix                    = "test1234"
  container_image               = "example.invalid/platform:test"
  repository_url                = "https://example.invalid/seaplane"
  app_code                      = "infra"
  service_phase                 = "dev"
  cost_center                   = "000"
  mc_ou_path                    = "o-example/r-example/ou-example/*"
  region_ou_path                = "o-example/r-example/ou-example/*"
  zoa_boundary_image            = "example.invalid/boundary:test"
  zoa_lambda_api_concurrency    = -1
  zoa_lambda_worker_concurrency = -1
  zoa_lambda_access_concurrency = -1
  account_access_environment_id = "ephemeral-test1234"
  account_access_table_region   = "us-west-2"
  account_access_table_arn      = "arn:aws:dynamodb:us-west-2:222222222222:table/shared-account-access"
}

run "disabled_by_default" {
  command = plan
  plan_options {
    target = [aws_eks_pod_identity_association.platform_api, aws_iam_role_policy.platform_api_account_access, aws_iam_role_policy.installer_jump]
  }

  assert {
    condition     = length(aws_iam_role.platform_api) == 0 && length(aws_iam_role.installer_jump) == 0 && length(aws_eks_pod_identity_association.platform_api) == 0
    error_message = "The PoC must create no roles or association unless explicitly enabled."
  }
}

run "isolated_two_hop_access" {
  command = plan
  plan_options {
    target = [aws_eks_pod_identity_association.platform_api, aws_iam_role_policy.platform_api_account_access, aws_iam_role_policy.installer_jump]
  }

  variables {
    enable_installer_role_poc    = true
    platform_api_namespace       = "custom-api"
    platform_api_service_account = "custom-api-sa"
  }

  assert {
    condition = (
      aws_eks_pod_identity_association.platform_api[0].disable_session_tags &&
      aws_eks_pod_identity_association.platform_api[0].namespace == "custom-api" &&
      aws_eks_pod_identity_association.platform_api[0].service_account == "custom-api-sa" &&
      jsondecode(aws_iam_role.platform_api[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111" &&
      jsondecode(aws_iam_role.platform_api[0].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == module.regional_cluster.cluster_arn
    )
    error_message = "Workload identity must restrict the source cluster/account, select the configured service account, and disable transitive tags."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.platform_api_account_access[0].policy).Statement) == 2 &&
      toset(jsondecode(aws_iam_role_policy.platform_api_account_access[0].policy).Statement[0].Action) == toset(["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]) &&
      jsondecode(aws_iam_role_policy.platform_api_account_access[0].policy).Statement[0].Resource == var.account_access_table_arn &&
      jsondecode(aws_iam_role_policy.platform_api_account_access[0].policy).Statement[1].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role_policy.platform_api_account_access[0].policy).Statement[1].Resource == aws_iam_role.installer_jump[0].arn
    )
    error_message = "Workload permissions must allow only the selected table's three operations and the exact jump role."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.installer_jump[0].assume_role_policy).Statement[0].Principal.AWS == aws_iam_role.platform_api[0].arn &&
      jsondecode(aws_iam_role.installer_jump[0].assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role_policy.installer_jump[0].policy).Statement[0].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role_policy.installer_jump[0].policy).Statement[0].Condition.StringEquals["iam:ResourceTag/seaplane-access"] == "true"
    )
    error_message = "The jump must trust only the workload and assume only access-tagged customer roles."
  }
}

run "reject_noncommercial_table_arn" {
  command = plan
  plan_options {
    target = [aws_eks_pod_identity_association.platform_api, aws_iam_role_policy.platform_api_account_access, aws_iam_role_policy.installer_jump]
  }

  variables {
    enable_installer_role_poc = true
    account_access_table_arn  = "arn:aws-us-gov:dynamodb:us-west-2:222222222222:table/shared-account-access"
  }

  expect_failures = [var.account_access_table_arn]
}

run "reject_environment_id_longer_than_api_limit" {
  command = plan
  plan_options {
    target = [aws_eks_pod_identity_association.platform_api, aws_iam_role_policy.platform_api_account_access, aws_iam_role_policy.installer_jump]
  }

  variables {
    enable_installer_role_poc     = true
    account_access_environment_id = join("", [for i in range(129) : "a"])
  }

  expect_failures = [var.account_access_environment_id]
}
