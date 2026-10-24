output "protection_group_id" {
  description = "The Clumio protection group's ID."
  value       = clumio_protection_group.this.id
}

output "name" {
  description = "The protection group and policy name in Clumio."
  value       = local.name
}

output "selection" {
  description = "What the group protects, in words."
  value       = local.selection
}
