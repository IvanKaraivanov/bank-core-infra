variable "environment" {
  description = "The name of the environment (e.g., dev, test, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "westeurope"
}

variable "dbx_public_subnet_prefix" {
  type        = string
  description = "Address prefix for Databricks Public (Host) Subnet"
  default     = "10.0.1.0/24"
}

variable "dbx_private_subnet_prefix" {
  type        = string
  description = "Address prefix for Databricks Private (Container) Subnet"
  default     = "10.0.2.0/24"
}

variable "databricks_admin_group" {
  type        = string
  description = "The name of the Databricks admin group to grant full permissions"
  default     = "admins"
}

variable "databricks_admin_users" {
  type        = list(string)
  description = "List of user emails to add to the admin group"
  default     = []
}