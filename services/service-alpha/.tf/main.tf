# We should have basic tagging, for example for finops or auditability
variable "service" {
  type    = string
  default = "service-alpha"
}
variable "team" {
  type    = string
  default = "example-team"
}
variable "cost_center" {
  type    = string
  default = "Engineering"
}
