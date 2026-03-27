module "base_infra" {
  source      = "../../modules/base-infra"
  environment = "test"
  location    = "westeurope"
  
  databricks_admin_users = [
    "nextgenlearning@ivanakaraivanovgmail.onmicrosoft.com"
  ]
}
