# aws-deployment-pipeline terraform module

## Overview

The `aws-deployment-pipeline` terraform module, which creates a set of resources that allow to automate the building process of containerized applications.

In the `main.tf` file there are definitions of the resources responsible for triggering the entire process, the most important of which are:
- `github_repository_webhook.github_proxy_api_gateway_webhook` - GitHub repository wehbook enabling the capture of `PUSH` actions,
- `api_gateway_webhook_proxy` module (build using [cloudposse/api-gateway/aws](https://github.com/cloudposse/terraform-aws-api-gateway) source module) - AWS Api Gateway Proxy used in GitHub repository wehbook configuration,
- `webhook_proxy_lambda` module (build using [terraform-aws-modules/lambda/aws"](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest) source module) - AWS Lambda, which triggers the deployment pipeline process using `lambda-webhook-proxy/index.js` code,
- `deployment_pipeline` module (build using local `./deployment_pipeline` module) - description of the most important file `main.tf` below.

The `deployment_pipeline/main.tf` file contains definitions of deployment pipelines built primarily using AWS CodePipeline and AWS Codebuild, as well as resources responsible for notifying the status of individual pipelines:
- `aws_codebuild_project.deployment_test_code` - AWS CodeBuild project for the application code testing stage,
- `aws_codebuild_project.deployment_docker_image_build` - AWS CodeBuild project for the application docker image build stage,
- `aws_codebuild_project.deployment_gitops_push` - AWS CodeBuild project for updating image tags in kustomization files,
- `aws_codepipeline.deployment_pipeline` - AWS CodePipeline project, which consists of 4 phases: `Source` (downloading source code from indicated GitHub respository), `Test`, `BuildImage` and `PushToGitOps`,
- `aws_s3_bucket.deployment_pipeline_artifacts` - AWS S3 Bucket for storing `aws_codepipeline.deployment_pipeline` artifacts,
- `aws_ecr_repository.ecr_repository` - AWS ECR registry for storing docker images,
- `deployment_pipeline_notifications` module build using [https://github.com/kjagiello/terraform-aws-codepipeline-slack-notifications](https://github.com/kjagiello/terraform-aws-codepipeline-slack-notifications) source module) - module used to send notifications about `aws_codepipeline.deployment_pipeline` status,
- `deployment_pipeline_notifications_failed` module build using [https://github.com/kjagiello/terraform-aws-codepipeline-slack-notifications](https://github.com/kjagiello/terraform-aws-codepipeline-slack-notifications) source module) - module used to send notifications about `aws_codepipeline.deployment_pipeline` in `failed` or `canceled` status.

## Usage

Required vars:
- name,
- env,
- vpc_id,
- vpc_private_subnets,
- default_security_group_id,
- github_repository_organization,
- github_repository_name,
- github_repository_branch,
- github_access_token,
- devops_slack_webhook,
- devops_slack_channel_name,
- devops_slack_webhook_failed,
- devops_slack_channel_name_failed,
- target_gitops_repository,
- github_access_token_secret_name,
- github_user,
- pipelines.*pipeline_name*.name,
- pipelines.*pipeline_name*.short_name,
- pipelines.*pipeline_name*.secret_arns[],
- pipelines.*pipeline_name*.file_path_pattern_trigger,
- pipelines.*pipeline_name*.buildspec,
- pipelines.*pipeline_name*.buildspec_test_code,
- pipelines.*pipeline_name*.environment_variables.

Optional vars, defaults values in brackets:
- cloudwatch_log_retention_in_days (60),
- pipelines.*pipeline_name*.enable_test_stage (false).

```hcl
module "deployment_pipeline_cosmos_graphql_repository" {
  source = "github.com/Airnauts/terraform-aws-deployment-pipeline.git?ref=v0.0.68"

  name = "cosmos-graphql"
  env  = "dev"

  vpc_id                    = module.vpc.vpc_id
  vpc_private_subnets       = module.vpc.private_subnets
  default_security_group_id = module.vpc.default_security_group_id

  github_repository_organization = "Airnauts"
  github_repository_name         = "cosmos-graphql"
  github_repository_branch       = "dev
  github_access_token            = local.github_access_token

  devops_slack_webhook             = local.devops_slack_webhook
  devops_slack_channel_name        = "#cosmos-devops"
  devops_slack_webhook_failed      = local.dev_backend_slack_webhook
  devops_slack_channel_name_failed = "#cosmos-dev-backend"

  target_gitops_repository        = "Airnauts"
  github_access_token_secret_name = "GITHUB_ACCESS_TOKEN"
  github_user                     = "airnauts-cosmosbot"

  cloudwatch_log_retention_in_days = 30

  pipelines = {
    analytics = {
      name                      = "app-name"
      shorter_name              = "app"
      secret_arns               = []
      file_path_pattern_trigger = ".*"
      buildspec                 = "buildspec.yml"
      buildspec_test_code       = "buildspec-test-code.yml"
      enable_test_stage         = true
      environment_variables     = [
        {
          name : "PATH",
          type : "PLAINTEXT",
          value : "."
        }
      ]
    }
}
```
