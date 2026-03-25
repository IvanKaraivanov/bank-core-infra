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

# ==========================================
# 7. DATABRICKS ACCESS CONNECTOR (The Bridge)
# ==========================================
# Creates a Managed Identity for Databricks to securely access the Data Lake (Unity Catalog standard)
resource "azurerm_databricks_access_connector" "unity" {
  name                = "dbac-bankcore-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  identity {
    type = "SystemAssigned"
  }
}

# ==========================================
# 8. ROLE ASSIGNMENT (The VIP Pass)
# ==========================================
# Grants the Access Connector read/write permissions to the Data Lake
resource "azurerm_role_assignment" "databricks_datalake_access" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.unity.identity[0].principal_id
}

# ==========================================
# 9. UNITY CATALOG & MEDALLION ARCHITECTURE
# ==========================================

# 1. Create the root filesystem (container) in the Data Lake
resource "azurerm_storage_data_lake_gen2_filesystem" "unity_data" {
  name               = "unity-catalog-data"
  storage_account_id = azurerm_storage_account.datalake.id
}

# 2. Register our Access Connector in Unity Catalog (Storage Credential)
resource "databricks_storage_credential" "mi_credential" {
  name = "cred-bankcore-${var.environment}"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.unity.id
  }
  comment    = "Managed identity credential for ${var.environment}"
  
  # Ensure the Azure role assignment exists before creating the credential
  depends_on = [azurerm_role_assignment.databricks_datalake_access]
}

# 3. Create the External Location (tells Databricks where the lake is and how to access it)
resource "databricks_external_location" "datalake_loc" {
  name            = "ext-bankcore-${var.environment}"
  url             = format("abfss://%s@%s.dfs.core.windows.net/", azurerm_storage_data_lake_gen2_filesystem.unity_data.name, azurerm_storage_account.datalake.name)
  credential_name = databricks_storage_credential.mi_credential.id
  comment         = "External location for Bank Core ${var.environment}"
}

# 4. Create the Environment-specific Catalog (Environment isolation)
resource "databricks_catalog" "env_catalog" {
  name         = "bankcore_${var.environment}"
  storage_root = databricks_external_location.datalake_loc.url
  comment      = "Main catalog for the ${var.environment} environment"
}

# 5. Create the Medallion schemas (Databases) WITHOUT environment suffixes
resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "bronze"
  comment      = "Bronze layer: Raw, unvalidated data"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "silver"
  comment      = "Silver layer: Cleaned, filtered, and conformed data"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "gold"
  comment      = "Gold layer: Business-level aggregates and Dimensional Model"
}

# ==========================================
# 10. GRANTS (Permissions for human users)
# ==========================================
# Grant permissions to the built-in "users" group so you can see and use the catalog
resource "databricks_grants" "catalog_access" {
  catalog = databricks_catalog.env_catalog.name

  grant {
    principal  = "account users"
    privileges = [
      "USE_CATALOG",    # Allows users to see the catalog
      "USE_SCHEMA",     # Allows users to see schemas inside
      "CREATE_SCHEMA",  # Allows users to create new schemas
      "CREATE_TABLE",   # Allows users to create tables
      "SELECT",         # Allows users to read data
      "MODIFY"          # Allows users to insert/update/delete data
    ]
  }
}

# ==========================================
# 11. SPARK CLUSTER (The Compute Engine)
# ==========================================

# Dynamically fetch the latest Long Term Support (LTS) Databricks Runtime version
data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

# Dynamically fetch the smallest available VM node type for the environment
data "databricks_node_type" "smallest" {
  local_disk = true
}

# Create an interactive Shared cluster for development, Databricks Connect and Asset Bundles
resource "databricks_cluster" "dev_cluster" {
  cluster_name            = "compute-bankcore-${var.environment}"
  spark_version           = data.databricks_spark_version.latest_lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  
  # FinOps best practice: Auto-terminate after 15 minutes of inactivity to save cloud costs
  autotermination_minutes = 15

  # Minimum 1 worker is required for USER_ISOLATION (Shared Compute) in Unity Catalog
  num_workers             = 1

  # Required security mode for Unity Catalog (Shared Compute)
  data_security_mode      = "USER_ISOLATION"

  custom_tags = {
    "Environment" = var.environment
    "Project"     = "BankCore"
  }
}

# ==========================================
# 12. CLUSTER PERMISSIONS (The missing piece)
# ==========================================
resource "databricks_permissions" "dev_cluster_access" {
  cluster_id = databricks_cluster.dev_cluster.id

  access_control {
    # Grant permissions to all  users in the workspace. 
    # If you have a specific engineering group, replace "account users" with it.
    group_name       = "users" 
    
    # CAN_RESTART allows users to see the cluster, attach to it 
    # (for Databricks Connect), and wake it up if it has auto-terminated.
    permission_level = "CAN_RESTART" 
  }
}