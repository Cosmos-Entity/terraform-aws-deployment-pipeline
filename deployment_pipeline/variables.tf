variable "name" {
  type = string
}

variable "cloudwatch_log_retention_in_days" {
  default = 180
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

variable "buildspec_test_build" {
  type = string
}

variable "github_access_token" {
  type = string
}

variable "buildspec_test_code" {
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

variable "env" {
  type = string
}
