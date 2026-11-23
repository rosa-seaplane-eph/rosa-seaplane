variable "environment_id" {
  description = "Unique environment identifier shared by all regional consumers. Determines the table name and state ownership."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$", var.environment_id))
    error_message = "environment_id must be 1-128 letters, digits, underscores or hyphens, starting with a letter or digit."
  }
}

variable "enable_pitr" {
  description = "Enable point-in-time recovery. Disable for disposable PoC environments."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the shared table from deletion. Final cleanup must explicitly disable protection first."
  type        = bool
  default     = true
}

variable "consumer_role_arns" {
  description = "Exact workload role ARNs allowed cross-account record access. Same-account consumers need only their identity policy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.consumer_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", arn))])
    error_message = "consumer_role_arns must contain IAM role ARNs."
  }
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
