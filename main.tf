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
  count = length(var.pipelines)
  source = "./deployment_pipeline"

  name                             = var.pipelines[count.index].name
  env                              = var.env
  vpc_id                           = var.vpc_id
  vpc_private_subnets              = var.vpc_private_subnets
  default_security_group_id        = var.default_security_group_id

  buildspec                        = var.pipelines[count.index].buildspec
  buildspec_test_build             = var.pipelines[count.index].buildspec_test_build
  buildspec_test_code              = var.pipelines[count.index].buildspec_test_code

  environment_variables            = var.pipelines[count.index].environment_variables
  secret_arns = var.pipelines[count.index].secret_arns

  github_repository_name           = var.github_repository_name
  github_organization_name         = var.github_repository_organization
  github_repository_branch         = var.github_repository_branch
  github_webhook_token             = var.github_webhook_token

  devops_slack_webhook = var.devops_slack_webhook
  devops_slack_channel_name = var.devops_slack_channel_name
}

module "api_gateway_account_settings" {
  source  = "cloudposse/api-gateway/aws//modules/account-settings"
  version = "0.3.1"
  context = module.api_gateway_webhook_proxy.context
}

module "api_gateway_webhook_proxy" {
  source = "cloudposse/api-gateway/aws"
  version = "0.3.1"

  stage = "default"
  name = "${var.name}-webhook-proxy"
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
    resources = module.deployment_pipeline.*.codepipeline_arn
    effect = "Allow"
  }
}

module "webhook_proxy_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.36.0"

  function_name = "${var.name}-webhook-proxy"
  description   = ""
  handler       = "index.githubWebhookListener"
  runtime       = "nodejs14.x"
  compatible_architectures = ["x86_64"]

  source_path = [
    {
      path     = "${path.module}/lambda-webhook-proxy"
      commands = [
        ":zip"
      ]
    }
  ]

  memory_size = 128
  timeout = 25

  lambda_at_edge = false
  publish = true

  environment_variables = merge(
    {for i, pipeline in var.pipelines: "TARGET_PIPELINE_NAME_${i}" => "${pipeline.name}"},
    {for i, pipeline in var.pipelines: "TARGET_PIPELINE_REGEXP_${i}" => pipeline.file_path_pattern_trigger},
    {GITHUB_WEBHOOK_SECRET = random_password.github_webhook_secret.result},
    {TARGET_GITHUB_REPOSITORY_BRANCH = var.github_repository_branch}
  )
  attach_policy_json = true
  policy_json = data.aws_iam_policy_document.lambda_webhook_proxy_role_iam_policy_document.json

  recreate_missing_package = true
  hash_extra = var.name

  attach_cloudwatch_logs_policy = true
  cloudwatch_logs_retention_in_days = var.cloudwatch_log_retention_in_days
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