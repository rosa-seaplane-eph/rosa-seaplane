variable "region" {
  description = "Hosting region of the single shared table."
  type        = string
}

variable "account_access_environment_id" {
  description = "Unique environment identifier, shared by all consumers of this table."
  type        = string
}

variable "account_access_enable_pitr" {
  description = "Enable point-in-time recovery on the environment-owned table."
  type        = bool
  default     = true
}

variable "account_access_deletion_protection" {
  description = "Protect the table until its owner explicitly performs final cleanup."
  type        = bool
  default     = true
}

variable "account_access_consumer_role_arns" {
  description = "Exact workload role ARNs needing cross-account access."
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Environment name for resource tags."
  type        = string
}

variable "eph_prefix" {
  description = "Unique ephemeral deployment prefix for cost attribution."
  type        = string
  default     = ""
}

variable "app_code" {
  description = "Application code for resource tags."
  type        = string
}

variable "service_phase" {
  description = "Service phase for resource tags."
  type        = string
}

variable "cost_center" {
  description = "Cost center for resource tags."
  type        = string
}
