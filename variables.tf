variable "name" {
  type = string
}
variable "pipelines" {
  type = map(object({
    name = string
    buildspec = string
    buildspec_test_build = string
    buildspec_test_code = string
    environment_variables = any
    secret_arns = list(string)
    file_path_pattern_trigger = string
  }))
}
variable "github_repository_name" {
  type = string
}
variable "github_webhook_token" {
  type = string
}
variable "github_repository_organization" {
  type = string
}
variable "github_repository_branch" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "vpc_private_subnets" {
  type = list(string)
}
variable "default_security_group_id" {
  type = string
}
variable "devops_slack_webhook" {
  type = string
}
variable "devops_slack_channel_name" {
  type = string
}
variable "env" {
  type = string
}
variable "cloudwatch_log_retention_in_days" {
  default = 180
}