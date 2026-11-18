output "tags" {
  description = "The mandatory tags. Pass them to your provider's default_tags so everything you build carries them."
  value       = local.tags
}

output "bucket" {
  description = "The bucket holding the reports and Athena results."
  value       = aws_s3_bucket.cur.bucket
}

output "athena_workgroup" {
  description = "Open Athena with this workgroup to run the saved queries."
  value       = aws_athena_workgroup.cost.name
}

output "athena_table" {
  description = "The table to query: database.table."
  value       = local.table
}
