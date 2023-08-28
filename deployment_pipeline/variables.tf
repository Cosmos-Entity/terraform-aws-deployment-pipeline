variable "name" {
  type = string
}

variable "cloudwatch_log_retention_in_days" {
  default = 90
  description = "CloudWatch log retention for pipelines /aws/lambda/*"
}

variable "vpc_private_subnets" {
  type = list(string)
}

variable "default_security_group_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "environment_variables" {
}

variable "buildspec" {
  type = string
}

variable "github_access_token" {
  type = string
}

variable "github_access_token_secret_name" {
  type = string
}

variable "buildspec_test_code" {
  type = string
}

variable "github_user" {
  type = string
}

variable "github_repository_branch" {
  type = string
}

variable "github_organization_name" {
  type = string
}

variable "github_repository_name" {
  type = string
}

variable "secret_arns" {
  type = list(string)
}

variable "devops_slack_webhook" {
  type = string
}

variable "devops_slack_channel_name" {
  type = string
}

variable "devops_slack_webhook_failed" {
  type = string
}

variable "devops_slack_channel_name_failed" {
  type = string
}

variable "env" {
  type = string
}

variable "enable_test_stage" {
  type = bool
  default = false
}

variable "target_gitops_repository" {
  type = string
  description = "Target gitops repository where the image tag update will be pushed (assumes existence of directory kustomization/kustomization.yaml"
}