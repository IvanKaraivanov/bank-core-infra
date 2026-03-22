module "base_infra" {
  source      = "../../modules/base-infra"
  environment = "dev"
  location    = "westeurope"
}
