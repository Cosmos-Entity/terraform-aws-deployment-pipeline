terraform {
  required_providers {
    github = {
      source  = "hashicorp/github"
      version = "4.24.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.22"
    }
  }
}
data "aws_region" "region" {}
data "aws_caller_identity" "identity" {}

module "deployment_pipeline" {
  for_each = var.pipelines
  source = "./deployment_pipeline"

  name                             = var.pipelines[each.key].name
  shorter_name                     = var.pipelines[each.key].shorter_name
  env                              = var.env
  vpc_id                           = var.vpc_id
  vpc_private_subnets              = var.vpc_private_subnets
  default_security_group_id        = var.default_security_group_id

  buildspec                        = var.pipelines[each.key].buildspec
  buildspec_test_code              = var.pipelines[each.key].buildspec_test_code
  enable_test_stage                = var.pipelines[each.key].enable_test_stage

  environment_variables            = var.pipelines[each.key].environment_variables
  secret_arns = var.pipelines[each.key].secret_arns

  github_repository_name          = var.github_repository_name
  github_user                     = var.github_user
  github_organization_name        = var.github_repository_organization
  github_repository_branch        = var.github_repository_branch
  github_access_token             = var.github_access_token
  github_access_token_secret_name = var.github_access_token_secret_name
  target_gitops_repository        = var.target_gitops_repository
  target_gitops_organization_name = var.target_gitops_organization_name

  devops_slack_webhook             = var.devops_slack_webhook
  devops_slack_channel_name        = var.devops_slack_channel_name
  devops_slack_webhook_failed      = var.devops_slack_webhook_failed
  devops_slack_channel_name_failed = var.devops_slack_channel_name_failed

  cloudwatch_log_retention_in_days = var.cloudwatch_log_retention_in_days
}

locals {
  context = {
    enabled             = true
    namespace           = null
    tenant              = null
    environment         = null
    stage               = "default"
    name                = "${var.name}-hook"
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    # Note: we have to use [] instead of null for unset lists due to
    # https://github.com/hashicorp/terraform/issues/28137
    # which was not fixed until Terraform 1.0.0,
    # but we want the default to be all the labels in `label_order`
    # and we want users to be able to prevent all tag generation
    # by setting `labels_as_tags` to `[]`, so we need
    # a different sentinel to indicate "default"
    labels_as_tags = ["unset"]
  }
}

module "api_gateway_webhook_proxy" {
  source = "cloudposse/api-gateway/aws"
  version = "0.3.1"

  context = local.context

  metrics_enabled = true

  openapi_config = {
    openapi = "3.0.1"
    info = {
      title   = "Image processor"
      version = "1.0"
    }
    paths = {
      "{proxy+}" = {
        x-amazon-apigateway-any-method = {
          x-amazon-apigateway-integration = {
            httpMethod           = "POST"
            payloadFormatVersion = "2.0"
            type                 = "aws_proxy"
            uri                  = "arn:aws:apigateway:${data.aws_region.region.name}:lambda:path/2015-03-31/functions/${module.webhook_proxy_lambda.lambda_function_arn}/invocations"
            timeoutInMillis      = 29000
          }
        }
      }
    }
  }
}

data "aws_iam_policy_document" "lambda_webhook_proxy_role_iam_policy_document" {
  statement {
    sid = "AllowPipelineExecution"

    actions = [
      "codepipeline:StartPipelineExecution",
    ]
    resources = [for k, pipeline in module.deployment_pipeline: pipeline.codepipeline_arn]
    effect = "Allow"
  }
}

module "lambda_function_archives" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "2.2.0"

  bucket        = "${var.name}-deployment-lambda-archives"
  force_destroy = true
}

module "webhook_proxy_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "4.0.1"

  function_name = "${var.name}-webhook-proxy"
  description   = ""
  handler       = "index.githubWebhookListener"
  runtime       = "nodejs20.x"
  compatible_architectures = ["x86_64"]

  source_path = "${path.module}/lambda-webhook-proxy"

  memory_size = 128
  timeout = 25

  store_on_s3 = true
  s3_bucket   = module.lambda_function_archives.s3_bucket_id
  artifacts_dir = "${path.root}/.terraform/${var.name}-deployment-lambda-artifacts/"

  lambda_at_edge = false
  publish = true

  environment_variables = merge(
    {for key, pipeline in var.pipelines: "TARGET_PIPELINE_NAME_${index(keys(var.pipelines), key)}" => pipeline.name},
    {for key, pipeline in var.pipelines: "TARGET_PIPELINE_REGEXP_${index(keys(var.pipelines), key)}" => pipeline.file_path_pattern_trigger},
    {GITHUB_WEBHOOK_SECRET = random_password.github_webhook_secret.result},
    {TARGET_GITHUB_REPOSITORY_BRANCH = var.github_repository_branch}
  )

  attach_policy_json = true
  policy_json = data.aws_iam_policy_document.lambda_webhook_proxy_role_iam_policy_document.json

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_retention_in_days = var.cloudwatch_log_retention_in_days

  recreate_missing_package = false
}

resource "aws_lambda_permission" "api_gateway_image_processor_res_lambda_permission" {
  statement_id  = "AllowAPIGatewayRESTInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.webhook_proxy_lambda.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${module.api_gateway_webhook_proxy.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "webhook_proxy_api_gateway" {
  name              = "${var.name}-webhook-proxy-api-gateway"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

resource "random_password" "github_webhook_secret" {
  length           = 32
  special          = false
}

resource "github_repository_webhook" "github_proxy_api_gateway_webhook" {
  repository = var.github_repository_name

  configuration {
    url          = "${module.api_gateway_webhook_proxy.invoke_url}/any"
    content_type = "json"
    insecure_ssl = false
    secret       = random_password.github_webhook_secret.result
  }

  events = ["push"]
  active = true
}