# ==========================================
# 1. RESOURCE GROUP
# ==========================================
resource "azurerm_resource_group" "main" {
  name     = "rg-bank-core-${var.environment}"
  location = var.location
}

# ==========================================
# 2. NETWORKING (VNet & Subnets)
# ==========================================
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-bank-core-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "databricks_nsg" {
  name                = "nsg-databricks-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Public Subnet for Databricks (Host)
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

# Private Subnet for Databricks (Container)
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

resource "azurerm_subnet_network_security_group_association" "dbx_public" {
  subnet_id                 = azurerm_subnet.dbx_public.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "dbx_private" {
  subnet_id                 = azurerm_subnet.dbx_private.id
  network_security_group_id = azurerm_network_security_group.databricks_nsg.id
}

# ==========================================
# 3. STORAGE (ADLS Gen2)
# ==========================================
resource "azurerm_storage_account" "datalake" {
  name                     = "dlsbankcore${var.environment}" 
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Critical for ADLS Gen2
}

resource "azurerm_storage_data_lake_gen2_filesystem" "unity_data" {
  name               = "unity-catalog-data"
  storage_account_id = azurerm_storage_account.datalake.id
}

# ==========================================
# 4. DATABRICKS WORKSPACE
# ==========================================
resource "azurerm_databricks_workspace" "databricks" {
  name                = "dbw-bankcore-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "premium"

  custom_parameters {
    no_public_ip        = true 
    virtual_network_id  = azurerm_virtual_network.vnet.id
    public_subnet_name  = azurerm_subnet.dbx_public.name
    private_subnet_name = azurerm_subnet.dbx_private.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbx_public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbx_private.id
  }
}

# ==========================================
# 5. ACCESS CONNECTOR & ROLE ASSIGNMENTS
# ==========================================
resource "azurerm_databricks_access_connector" "unity" {
  name                = "dbac-bankcore-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  identity { type = "SystemAssigned" }
}

resource "azurerm_role_assignment" "databricks_datalake_access" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.unity.identity[0].principal_id
}

# ==========================================
# 6. UNITY CATALOG SETUP
# ==========================================
resource "databricks_storage_credential" "mi_credential" {
  name = "cred-bankcore-${var.environment}"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.unity.id
  }
  depends_on = [azurerm_role_assignment.databricks_datalake_access]
}

resource "databricks_external_location" "datalake_loc" {
  name            = "ext-bankcore-${var.environment}"
  url             = format("abfss://%s@%s.dfs.core.windows.net/", azurerm_storage_data_lake_gen2_filesystem.unity_data.name, azurerm_storage_account.datalake.name)
  credential_name = databricks_storage_credential.mi_credential.id
}

resource "databricks_catalog" "env_catalog" {
  name         = "bankcore_${var.environment}"
  storage_root = databricks_external_location.datalake_loc.url
}

# Medallion Architecture Schemas
resource "databricks_schema" "bronze" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "bronze"
}

resource "databricks_schema" "silver" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "silver"
}

resource "databricks_schema" "gold" {
  catalog_name = databricks_catalog.env_catalog.name
  name         = "gold"
}

# ==========================================
# 7. ADMINISTRATIVE PERMISSIONS (YOUR ACCESS)
# ==========================================

# Create Admin Users in the Workspace
resource "databricks_user" "admins" {
  for_each  = toset(var.databricks_admin_users)
  user_name = each.value
}

# Fetch the built-in 'admins' group
data "databricks_group" "admins" {
  display_name = "admins"
}

# Assign Users to the Admin Group (Full Workspace Admin)
resource "databricks_group_member" "admin_membership" {
  for_each  = toset(var.databricks_admin_users)
  group_id  = data.databricks_group.admins.id
  member_id = databricks_user.admins[each.value].id
}

# Grant ALL PRIVILEGES on Unity Catalog objects
resource "databricks_grants" "catalog_access" {
  catalog = databricks_catalog.env_catalog.name

  # Admin full access
  dynamic "grant" {
    for_each = toset(var.databricks_admin_users)
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES"]
    }
  }
  # General users access
  grant {
    principal  = "account users"
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}

resource "databricks_grants" "external_loc_grants" {
  external_location = databricks_external_location.datalake_loc.id
  dynamic "grant" {
    for_each = toset(var.databricks_admin_users)
    content {
      principal  = grant.value
      privileges = ["ALL_PRIVILEGES"]
    }
  }
}

# ==========================================
# 8. COMPUTE (Spark Cluster)
# ==========================================
data "databricks_spark_version" "latest_lts" {
  long_term_support = true
  depends_on        = [azurerm_databricks_workspace.databricks]
}

data "databricks_node_type" "smallest" {
  local_disk = true
  depends_on = [azurerm_databricks_workspace.databricks]
}

resource "databricks_cluster" "dev_cluster" {
  cluster_name            = "compute-bankcore-${var.environment}"
  spark_version           = data.databricks_spark_version.latest_lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 15
  num_workers             = 1
  data_security_mode      = "USER_ISOLATION" # Required for Unity Catalog
}

# Grant Cluster Management rights to Admins
resource "databricks_permissions" "cluster_usage" {
  cluster_id = databricks_cluster.dev_cluster.id

  access_control {
    group_name       = "users"
    permission_level = "CAN_RESTART"
  }

  dynamic "access_control" {
    for_each = toset(var.databricks_admin_users)
    content {
      user_name        = access_control.value
      permission_level = "CAN_MANAGE" # Allows you to edit the cluster
    }
  }
}