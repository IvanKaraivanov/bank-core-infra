terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state-bank"
    storage_account_name = "tfstatebankcoreinfra"
    container_name       = "tfstate-test"
    key                  = "terraform.tfstate"
  }
}
