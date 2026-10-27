# Retired: the platform image is built by Konflux. This module keeps only the
# provider configuration that existing states need to destroy the former
# build-platform-image resources (CodeBuild project, IAM role and policy).
# Remove it, and its module call in central-account-bootstrap, once every
# environment has applied without those resources.
provider "aws" {
  region = var.region
  # FedRAMP SC-13 / IA-07: Use FIPS 140-2 validated endpoints when available.
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region)) ? true : false
}
