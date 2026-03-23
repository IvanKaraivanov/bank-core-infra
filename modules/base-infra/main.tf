# 1. Create a Resource Group for the core infrastructure
resource "azurerm_resource_group" "main" {
  name     = "rg-bank-core-${var.environment}"
  location = var.location
}

# 2. Create a Virtual Network (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-bank-core-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}