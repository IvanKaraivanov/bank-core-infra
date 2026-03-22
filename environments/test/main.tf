module "base_infra" {
  source      = "../../modules/base-infra"
  environment = "test"
  location    = "westeurope"
}
