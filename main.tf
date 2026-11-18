# CoverOps Marketplace kit: Cost and Usage Report 2.0 + Athena.
# A daily CUR 2.0 export (Parquet) to an encrypted bucket, an Athena table over it that needs no
# crawler (partition projection), a workgroup that refuses queries scanning over 1 GB, and saved
# queries: cost by service, top resources, untagged spend. Apache 2.0.

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

locals {
  tags = merge(var.extra_tags, {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCentre  = var.cost_centre
    ManagedBy   = "terraform"
    Kit         = "coverops/aws-cur-athena"
  })
  acct   = data.aws_caller_identity.this.account_id
  arn    = "arn:${data.aws_partition.this.partition}"
  name   = "${var.project}-${var.environment}-cur"
  bucket = coalesce(var.bucket_name, "${var.project}-cur-${local.acct}")
  export = replace(local.name, "-", "_")
  db     = replace("${var.project}_${var.environment}_cost", "-", "_")
  # CUR 2.0 writes <prefix>/<export>/data/BILLING_PERIOD=YYYY-MM/*.parquet
  data_path = "s3://${local.bucket}/cur/${local.export}/data"

  # The columns exported and their Athena types. CUR 2.0 has many more; add any you need here.
  columns = {
    identity_line_item_id                    = "string"
    identity_time_interval                   = "string"
    bill_billing_period_start_date           = "timestamp"
    bill_payer_account_id                    = "string"
    line_item_usage_account_id               = "string"
    line_item_line_item_type                 = "string"
    line_item_usage_start_date               = "timestamp"
    line_item_product_code                   = "string"
    line_item_usage_type                     = "string"
    line_item_operation                      = "string"
    line_item_resource_id                    = "string"
    line_item_line_item_description          = "string"
    line_item_usage_amount                   = "double"
    line_item_unblended_cost                 = "double"
    product_region_code                      = "string"
    pricing_unit                             = "string"
    reservation_effective_cost               = "double"
    savings_plan_savings_plan_effective_cost = "double"
    resource_tags                            = "map<string,string>"
  }
}

# --- Bucket -------------------------------------------------------------------

resource "aws_s3_bucket" "cur" {
  bucket        = local.bucket
  force_destroy = var.force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    id     = "athena-results"
    status = "Enabled"
    filter {
      prefix = "athena-results/"
    }
    expiration {
      days = var.results_expire_days
    }
  }
  rule {
    id     = "abort-unfinished-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Only AWS billing, for this account's exports, may write here.
data "aws_iam_policy_document" "cur" {
  statement {
    sid = "DataExportsWrite"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com", "bcm-data-exports.amazonaws.com"]
    }
    actions   = ["s3:PutObject", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [local.acct]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "${local.arn}:cur:us-east-1:${local.acct}:definition/*",
        "${local.arn}:bcm-data-exports:us-east-1:${local.acct}:export/*",
      ]
    }
  }
  statement {
    sid     = "HttpsOnly"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cur" {
  bucket     = aws_s3_bucket.cur.id
  policy     = data.aws_iam_policy_document.cur.json
  depends_on = [aws_s3_bucket_public_access_block.cur]
}

# --- The export (a global service: AWS runs Data Exports in us-east-1) ------------

resource "aws_bcmdataexports_export" "cur" {
  export {
    name        = local.export
    description = "CUR 2.0, daily, Parquet (coverops/aws-cur-athena)"

    data_query {
      query_statement = "SELECT ${join(", ", keys(local.columns))} FROM COST_AND_USAGE_REPORT"
      table_configurations = {
        COST_AND_USAGE_REPORT = {
          TIME_GRANULARITY                      = "DAILY"
          INCLUDE_RESOURCES                     = "TRUE"
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE"
          # AWS adds this to every export; set it so Terraform sees what AWS returns (the account's primary view).
          BILLING_VIEW_ARN = "${local.arn}:billing::${local.acct}:billingview/primary"
        }
      }
    }

    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.cur.bucket
        s3_prefix = "cur"
        s3_region = data.aws_region.this.region
        s3_output_configurations {
          overwrite   = "OVERWRITE_REPORT"
          format      = "PARQUET"
          compression = "PARQUET"
          output_type = "CUSTOM"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }

  tags       = local.tags
  depends_on = [aws_s3_bucket_policy.cur]
}

# --- Athena ---------------------------------------------------------------------

resource "aws_glue_catalog_database" "cost" {
  name = local.db
  tags = local.tags
}

# Partition projection: Athena works out the month folders itself, so no crawler runs or bills.
resource "aws_glue_catalog_table" "cur" {
  name          = "cur"
  database_name = aws_glue_catalog_database.cost.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                          = "parquet"
    "projection.enabled"                      = "true"
    "projection.billing_period.type"          = "date"
    "projection.billing_period.format"        = "yyyy-MM"
    "projection.billing_period.range"         = "2024-01,NOW"
    "projection.billing_period.interval"      = "1"
    "projection.billing_period.interval.unit" = "MONTHS"
    "storage.location.template"               = "${local.data_path}/BILLING_PERIOD=$${billing_period}"
  }

  partition_keys {
    name = "billing_period"
    type = "string"
  }

  storage_descriptor {
    location      = local.data_path
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.columns
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}

resource "aws_athena_workgroup" "cost" {
  name          = local.name
  force_destroy = true # its saved queries and history go with it

  configuration {
    enforce_workgroup_configuration = true
    bytes_scanned_cutoff_per_query  = 1073741824 # 1 GB: a runaway query costs at most about half a US cent
    result_configuration {
      output_location = "s3://${aws_s3_bucket.cur.bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.tags
}

locals {
  table      = "${aws_glue_catalog_database.cost.name}.${aws_glue_catalog_table.cur.name}"
  this_month = "billing_period = date_format(current_date, '%Y-%m')"
  queries = {
    "cost-by-service-this-month"  = "SELECT line_item_product_code AS service, round(sum(line_item_unblended_cost), 2) AS usd FROM ${local.table} WHERE ${local.this_month} GROUP BY 1 ORDER BY 2 DESC"
    "top-20-resources-this-month" = "SELECT line_item_resource_id AS resource, line_item_product_code AS service, round(sum(line_item_unblended_cost), 2) AS usd FROM ${local.table} WHERE ${local.this_month} AND line_item_resource_id <> '' GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20"
    "untagged-spend-this-month"   = "SELECT line_item_product_code AS service, round(sum(line_item_unblended_cost), 2) AS usd FROM ${local.table} WHERE ${local.this_month} AND element_at(resource_tags, 'user_project') IS NULL GROUP BY 1 ORDER BY 2 DESC"
    "daily-cost-last-30-days"     = "SELECT date(line_item_usage_start_date) AS day, round(sum(line_item_unblended_cost), 2) AS usd FROM ${local.table} WHERE line_item_usage_start_date >= current_date - interval '30' day GROUP BY 1 ORDER BY 1"
  }
}

resource "aws_athena_named_query" "q" {
  for_each  = local.queries
  name      = each.key
  workgroup = aws_athena_workgroup.cost.id
  database  = aws_glue_catalog_database.cost.name
  query     = each.value
}
