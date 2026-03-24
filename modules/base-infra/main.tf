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

# 1. Network Security Group for Databricks (Required for VNet Injection)
resource "azurerm_network_security_group" "databricks_nsg" {
  name                = "nsg-databricks-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# 2. Databricks Public Subnet (Host) with subnet delegation
resource "azurerm_subnet" "dbx_public" {
  name                 = "snet-dbx-public-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.dbx_public_subnet_prefix]

  delegation {
    name = "databricks-del-public"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# 3. Databricks Private Subnet (Container) with subnet delegation
resource "azurerm_subnet" "dbx_private" {
  name                 = "snet-dbx-private-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.dbx_private_subnet_prefix]

  delegation {
    name = "databricks-del-private"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

# 4. Associate the NSG with both Databricks subnets
resource "azurerm_subnet_network_security_group_association" "dbx_public" {
  subnet_id                 = azurerm_subnet.dbx_public.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "dbx_private" {
  subnet_id                 = azurerm_subnet.dbx_private.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

# ==========================================
# 5. THE DATA LAKE (Azure Data Lake Storage Gen2)
# ==========================================
resource "azurerm_storage_account" "datalake" {
  # Note: Storage account names must be globally unique, lowercase letters and numbers only.
  name                     = "dlsbankcore${var.environment}" 
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  # THIS is the critical setting that enables Hierarchical Namespace (ADLS Gen2)
  is_hns_enabled           = true 
}

# ==========================================
# 6. DATABRICKS WORKSPACE (The Engine)
# ==========================================
resource "azurerm_databricks_workspace" "databricks" {
  name                = "dbw-bankcore-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Premium SKU is required for VNet Injection and Role-Based Access Control (RBAC)
  sku                 = "premium"

  # VNet Injection configuration.
  # Instructs Databricks to deploy its clusters into our custom, isolated subnets.
  custom_parameters {
    # Security best practice: Do not assign public IP addresses to the cluster nodes
    no_public_ip                                         = true 
    virtual_network_id                                   = azurerm_virtual_network.vnet.id
    public_subnet_name                                   = azurerm_subnet.dbx_public.name
    private_subnet_name                                  = azurerm_subnet.dbx_private.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbx_public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbx_private.id
  }
}