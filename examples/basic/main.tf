# The bill as a table: CUR 2.0 into S3 and Athena, for a startup's production account.
# The first data arrives within 24 hours; AWS can backfill earlier months on request (Billing support case).
locals {
  project     = "acme"
  environment = "production"
  owner       = "platform@acme.example"
}

provider "aws" {
  region = "ap-south-2"

  # The same mandatory tags on everything else you create with this provider.
  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      Owner       = local.owner
      CostCentre  = "engineering"
      ManagedBy   = "terraform"
    }
  }
}

module "cost_report" {
  source = "../.."
  # After publishing: source = "github.com/Cover-Ops/terraform-aws-cur-athena?ref=v0.1.0"

  project     = local.project
  environment = local.environment
  owner       = local.owner
}
