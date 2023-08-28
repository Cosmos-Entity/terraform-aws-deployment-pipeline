variable "name" {
  type = string
  description = "Name used for resource naming"
}

variable "pipelines" {
  type = map(object({
    name = string
    buildspec = string
    buildspec_test_code = string
    environment_variables = list(object({name = string, type = string, value = string}))
    secret_arns = list(string)
    file_path_pattern_trigger = string
    enable_test_stage = bool
  }))
}

variable "github_user" {
  type = string
}

variable "github_repository_name" {
  type = string
  description = "Github repository to be tracked"
}

variable "github_access_token_secret_name" {
  type = string
  description = "Name of the AWS Secrets manager secret that the gitops push job will use to manipulate target gitops repository files. It is mandatory that the secrets_arns also contain this name, otherwise codebuild will not be able to access them"
}

variable "github_access_token" {
  type = string
  description = "Github access token with admin permissions for target repository (used for downloading source code by codebuild job)"
}

variable "github_repository_organization" {
  type = string
  description = "Github organization hosting the target repository"
}
variable "github_repository_branch" {
  type = string
  description = "Git branch for which PUSH_EVENT should be tracked"
}
variable "vpc_id" {
  type = string
  description = "VPC ID, to be used to attach a network interface for CodePipeline project in order to access private subnets from within the job"
}
variable "vpc_private_subnets" {
  type = list(string)
  description = "VPC private subnets"
}

variable "default_security_group_id" {
  type = string
  description = "Default security group id to be used by CodePipeline project"
}

variable "devops_slack_webhook" {
  type = string
  description = "Slack webhook where pipeline progress statuses are to be reported"
}

variable "devops_slack_channel_name" {
  type = string
  description = "Slack channel name"
}

variable "devops_slack_webhook_failed" {
  type = string
  description = "Slack webhook where failed pipelines are to be reported"
}

variable "devops_slack_channel_name_failed" {
  type = string
  description = "Slack channel name for failed pipelines notifications"
}

variable "env" {
  type = string
  description = "Environment name used for resource naming"
}

variable "cloudwatch_log_retention_in_days" {
  default = 90
  description = "CloudWatch log retention for /aws/lambda/* and cosmos-*-webhook-proxy-api-gateway"
}

variable "target_gitops_repository" {
  type = string
  description = "Target gitops repository where the image tag update will be pushed (assumes existence of directory kustomization/kustomization.yaml"
}
