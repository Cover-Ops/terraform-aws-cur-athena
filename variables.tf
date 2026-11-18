variable "project" {
  description = "Short name of the product or company, used in names and the Project tag (lowercase, digits, hyphens)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project))
    error_message = "Use 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Which environment this is: production, staging or development."
  type        = string
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Use production, staging or development."
  }
}

variable "owner" {
  description = "Who answers for spend on what this kit manages: a team or a person's email. Goes in the Owner tag."
  type        = string
}

variable "cost_centre" {
  description = "Cost centre or budget line for the CostCentre tag, e.g. engineering."
  type        = string
  default     = "engineering"
}

variable "bucket_name" {
  description = "Name of the new S3 bucket for the report and Athena results. Leave null for <project>-cur-<account id>."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Let `terraform destroy` delete the bucket with the reports in it. Leave false outside tests."
  type        = bool
  default     = false
}

variable "results_expire_days" {
  description = "Delete Athena query results after this many days (the reports themselves are kept)."
  type        = number
  default     = 30
}

variable "extra_tags" {
  description = "More tags to add to everything this kit creates."
  type        = map(string)
  default     = {}
}
