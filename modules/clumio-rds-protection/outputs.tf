output "policy_id" {
  description = "The Clumio policy's ID."
  value       = clumio_policy.this.id
}

output "rule_id" {
  description = "The Clumio policy rule's ID."
  value       = clumio_policy_rule.this.id
}

output "name" {
  description = "The policy and rule name in Clumio."
  value       = local.name
}

output "selection" {
  description = "Which databases the rule matches, in words."
  value       = local.selection
}
