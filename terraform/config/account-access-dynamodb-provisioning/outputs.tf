output "table_arn" {
  description = "Environment-owned association table ARN."
  value       = module.account_access.table_arn
}

output "table_region" {
  description = "Hosting region for deployment configuration."
  value       = module.account_access.table_region
}
