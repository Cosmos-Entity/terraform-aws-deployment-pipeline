variable "name" {
}
variable "cloudwatch_log_retention_in_days" {
  default = 180
}
variable "vpc_private_subnets" {
}
variable "default_security_group_id" {
}
variable "vpc_id" {
}
variable "environment_variables" {
}
variable "buildspec" {
}
variable "buildspec_test_build" {
}
variable "github_webhook_token" {
}
variable "buildspec_test_code" {
}
variable "github_repository_branch" {
}
variable "github_organization_name" {
}
variable "github_repository_name" {
}
variable "secret_arns" {
  type = list(string)
}
variable "devops_slack_webhook" {
}
variable "devops_slack_channel_name" {
}
variable "env" {
}
