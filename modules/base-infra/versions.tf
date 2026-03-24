terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
    # Add the Databricks provider to manage resources inside the workspace
    databricks = {
      source = "databricks/databricks"
    }
  }
}

# Configure the Databricks provider to authenticate using the Azure workspace we just created
provider "databricks" {
  host                        = azurerm_databricks_workspace.databricks.workspace_url
  azure_workspace_resource_id = azurerm_databricks_workspace.databricks.id
}
