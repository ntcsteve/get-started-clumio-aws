output "tags" {
  description = "The tags on every AWS resource. ./lab puts them on what it creates: the rebuilt bucket and added instances."
  value       = local.tags
}
