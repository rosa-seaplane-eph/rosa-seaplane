output "table_arn" {
  description = "Shared association table ARN; regional services consume this exact reference."
  value       = aws_dynamodb_table.account_access.arn
}

output "table_region" {
  description = "Hosting AWS region, independent of each service's region."
  value       = split(":", aws_dynamodb_table.account_access.arn)[3]
}
