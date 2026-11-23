resource "aws_dynamodb_table" "account_access" {
  name                        = "${var.environment_id}-account-access"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "pk"
  range_key                   = "sk"
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.enable_pitr
  }

  # Default AWS-owned encryption supports cross-account resource policies.
  # The AWS-managed alias/aws/dynamodb key does not support those consumers.

  tags = merge(var.tags, {
    Name          = "${var.environment_id}-account-access"
    EnvironmentID = var.environment_id
    Component     = "account-access"
    function      = "platform-api"
    module        = "account-access-dynamodb"
    ManagedBy     = "terraform"
  })
}

# Optional cross-account consumers need this in addition to their workload
# identity policy. Exact PrincipalArn conditions allow provisioning the table
# before those roles exist, without granting the rest of their accounts access.
resource "aws_dynamodb_resource_policy" "consumers" {
  count        = length(var.consumer_role_arns) > 0 ? 1 : 0
  resource_arn = aws_dynamodb_table.account_access.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAccountAccessWorkloads"
      Effect    = "Allow"
      Principal = { AWS = distinct([for arn in var.consumer_role_arns : "arn:${split(":", arn)[1]}:iam::${split(":", arn)[4]}:root"]) }
      Action    = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource  = aws_dynamodb_table.account_access.arn
      Condition = {
        ArnEquals = { "aws:PrincipalArn" = var.consumer_role_arns }
      }
    }]
  })
}
