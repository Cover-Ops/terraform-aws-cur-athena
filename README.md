# Cost and Usage Report 2.0 with Athena

A CoverOps Marketplace kit. Cost Explorer answers the common questions; the Cost and Usage Report answers every other one, line by line. This kit sets up the report (CUR 2.0) in Parquet, an Athena table that finds new months by itself, and saved queries for the questions people ask first. Terraform ≥ 1.6 or OpenTofu ≥ 1.6, AWS provider 6.x. Apache 2.0.

> Status: **v0.1.0, tested on 2026-11-18**: applied, re-planned with no changes and destroyed on a sandbox AWS account (ap-south-1), nothing left behind. Run `terraform plan` before you apply it to your account.

## What it creates

| Resource | Why | Cost |
|---|---|---|
| Data Exports CUR 2.0 export, daily, Parquet, with resource ids | Every line of the bill, refreshed daily | Free (export) |
| S3 bucket, encrypted, public access blocked, HTTPS only, writable only by AWS billing for this account | Holds the report and query results | Under ₹50/month for most startups (S3 storage) |
| Glue database and table with partition projection | Athena finds each month's folder itself: no crawler runs or bills | Free |
| Athena workgroup: queries scanning over 1 GB are refused, results deleted after 30 days | A runaway query cannot run up a bill | US$5 per TB scanned, list price |
| Four saved queries | Cost by service this month, top 20 resources, untagged spend, daily cost for 30 days | Free |

**Estimated monthly cost: ₹0–100** (estimate, at AWS list prices). Estimate at AWS list prices: S3 storage for the reports, and Athena at US$5 per TB scanned (the saved queries scan megabytes).

## Mandatory tags
The kit's `tags` output is `Project`, `Environment`, `Owner`, `CostCentre`, `ManagedBy` and `Kit`. Put the same tags in your provider's `default_tags` (see the example) so everything you create carries them. The CoverOps Platform reads these tags to say who owns each rupee.

## Use

```hcl
module "cost_report" {
  source = "github.com/Cover-Ops/terraform-aws-cur-athena?ref=v0.1.0"

  project     = "acme"
  environment = "production"
  owner       = "platform@acme.example"
}
```

Full example: [`examples/basic`](examples/basic).

## Inputs

| Name | Description | Default |
|---|---|---|
| `project` | Short name of the product or company, used in names and the Project tag (lowercase, digits, hyphens). | required |
| `environment` | Which environment this is: production, staging or development. | required |
| `owner` | Who answers for spend on what this kit manages: a team or a person's email. Goes in the Owner tag. | required |
| `cost_centre` | Cost centre or budget line for the CostCentre tag, e.g. engineering. | `engineering` |
| `bucket_name` | Name of the new S3 bucket for the report and Athena results. Leave null for <project>-cur-<account id>. | `null` |
| `force_destroy` | Let `terraform destroy` delete the bucket with the reports in it. Leave false outside tests. | `false` |
| `results_expire_days` | Delete Athena query results after this many days (the reports themselves are kept). | `30` |
| `extra_tags` | More tags to add to everything this kit creates. | `{}` |

## Outputs
`tags`, `bucket`, `athena_workgroup`, `athena_table`.

## Good to know
- The first data arrives within 24 hours. AWS can fill in earlier months on request (a Billing support case).
- Data Exports always runs in us-east-1; the bucket and Athena are in the region you apply in.
- The untagged-spend query looks for a `project` cost allocation tag (`user_project`). Activate your tags under Billing → Cost allocation tags so they reach the report.
- Only some CUR 2.0 columns are exported, to keep queries cheap. Add columns in `local.columns` in `main.tf` (the export and the table follow).
- The bucket is kept on `terraform destroy` unless `force_destroy = true`.

## Support
Open an issue on GitHub. Want CoverOps engineers to apply it for you? See the setup service on marketplace.coverops.dev.
