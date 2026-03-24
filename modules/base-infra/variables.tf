variable "environment" {
  description = "The name of the environment (e.g., dev, test, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "westeurope"
}