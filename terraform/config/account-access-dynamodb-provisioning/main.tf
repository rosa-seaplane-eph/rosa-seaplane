# Environment-owned state, deliberately separate from regional-cluster state.
# Removing one regional deployment must not destroy shared account assignments.
provider "aws" {
  region            = var.region
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region)) ? true : false

  default_tags {
    tags = merge({
      app-code      = var.app_code
      service-phase = var.service_phase
      cost-center   = var.cost_center
      environment   = var.environment
      function      = "platform-api"
      module        = "account-access-dynamodb-provisioning"
    }, var.eph_prefix != "" ? { ephemeral-prefix = var.eph_prefix } : {})
  }
}

module "account_access" {
  source = "../../modules/account-access-dynamodb"

  environment_id      = var.account_access_environment_id
  enable_pitr         = var.account_access_enable_pitr
  deletion_protection = var.account_access_deletion_protection
  consumer_role_arns  = var.account_access_consumer_role_arns
}
