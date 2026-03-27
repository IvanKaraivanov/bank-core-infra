module "base_infra" {
  source      = "../../modules/base-infra"
  environment = "dev"
  location    = "westeurope"
  
  # Add your email here to be included in the admin group
  databricks_admin_users = [
    "nextgenlearning@ivanakaraivanovgmail.onmicrosoft.com"
  ]
}
