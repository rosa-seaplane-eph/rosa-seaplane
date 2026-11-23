mock_provider "aws" {
  override_during = plan
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-west-2:111111111111:table/ephemeral-test1234-account-access"
    }
  }
}

variables {
  region                        = "us-west-2"
  environment                   = "ephemeral"
  account_access_environment_id = "ephemeral-test1234"
  eph_prefix                    = "test1234"
  app_code                      = "infra"
  service_phase                 = "dev"
  cost_center                   = "000"
}

run "protected_environment_table" {
  command = plan

  assert {
    condition     = output.table_region == "us-west-2" && endswith(output.table_arn, "/ephemeral-test1234-account-access")
    error_message = "The owner must export the actual table ARN and hosting region."
  }
}

run "cross_account_consumer_policy" {
  command = plan

  variables {
    account_access_enable_pitr         = false
    account_access_deletion_protection = false
    account_access_consumer_role_arns  = ["arn:aws:iam::222222222222:role/us-east-1-test1234-platform-api"]
  }

  assert {
    condition     = output.table_region == "us-west-2"
    error_message = "Consumer configuration must not move the hosting table."
  }
}

run "protected_single_table" {
  variables {
    environment_id = "ephemeral-test1234"
  }
  command = plan

  module {
    source = "../../modules/account-access-dynamodb"
  }

  assert {
    condition = (
      aws_dynamodb_table.account_access.billing_mode == "PAY_PER_REQUEST" &&
      aws_dynamodb_table.account_access.hash_key == "pk" &&
      aws_dynamodb_table.account_access.range_key == "sk" &&
      length(aws_dynamodb_table.account_access.global_secondary_index) == 0 &&
      length(aws_dynamodb_table.account_access.replica) == 0
    )
    error_message = "The association store must be one on-demand pk/sk table without indexes or replicas."
  }

  assert {
    condition = (
      aws_dynamodb_table.account_access.deletion_protection_enabled &&
      one(aws_dynamodb_table.account_access.point_in_time_recovery).enabled &&
      length(aws_dynamodb_resource_policy.consumers) == 0
    )
    error_message = "Default protection must be enabled, without a cross-account grant."
  }
}

run "disposable_table_exact_consumer" {
  command = plan

  module {
    source = "../../modules/account-access-dynamodb"
  }

  variables {
    environment_id      = "ephemeral-test1234"
    enable_pitr         = false
    deletion_protection = false
    consumer_role_arns  = ["arn:aws:iam::222222222222:role/us-east-1-test1234-platform-api"]
  }

  assert {
    condition = (
      !aws_dynamodb_table.account_access.deletion_protection_enabled &&
      !one(aws_dynamodb_table.account_access.point_in_time_recovery).enabled &&
      jsondecode(aws_dynamodb_resource_policy.consumers[0].policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == ["arn:aws:iam::222222222222:role/us-east-1-test1234-platform-api"] &&
      toset(jsondecode(aws_dynamodb_resource_policy.consumers[0].policy).Statement[0].Action) == toset(["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]) &&
      jsondecode(aws_dynamodb_resource_policy.consumers[0].policy).Statement[0].Resource == aws_dynamodb_table.account_access.arn
    )
    error_message = "Disposable protection controls must work and cross-account access must remain scoped to exact consumers, table and operations."
  }
}

run "reject_account_wide_consumer" {
  command = plan

  module {
    source = "../../modules/account-access-dynamodb"
  }

  variables {
    environment_id     = "ephemeral-test1234"
    consumer_role_arns = ["arn:aws:iam::222222222222:root"]
  }

  expect_failures = [var.consumer_role_arns]
}

run "api_environment_id_format" {
  command = plan

  module {
    source = "../../modules/account-access-dynamodb"
  }

  variables {
    environment_id = "Ephemeral_TEST-123"
  }

  assert {
    condition     = aws_dynamodb_table.account_access.name == "Ephemeral_TEST-123-account-access"
    error_message = "Table provisioning must accept the API's environment ID characters."
  }
}

run "reject_environment_id_longer_than_api_limit" {
  command = plan

  module {
    source = "../../modules/account-access-dynamodb"
  }

  variables {
    environment_id = join("", [for i in range(129) : "a"])
  }

  expect_failures = [var.environment_id]
}
