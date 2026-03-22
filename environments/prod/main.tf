module "base_infra" {
  source      = "../../modules/base-infra"
  environment = "prod"
  location    = "westeurope"
}
