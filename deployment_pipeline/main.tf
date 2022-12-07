data "aws_caller_identity" "aws_identity" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "codepipeline_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "codepipeline.amazonaws.com"]
    }
  }
}

data "aws_kms_alias" "s3kmskey" {
  name = "alias/aws/s3"
}

resource "aws_ecr_repository" "ecr_repository" {
  name  = var.name
}

resource "aws_ecr_lifecycle_policy" "geco_docker_lifecycle_policy" {
  repository = aws_ecr_repository.ecr_repository.name
  policy     = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep latest 24 images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 24
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_iam_role" "deployment_pipeline_role" {
  name               = "${var.name}-deployment-pipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role_policy.json
}


data "aws_iam_policy_document" "deployment_pipeline_policy" {
  # TODO: Fix permissions
  statement {
    sid = "1"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage"
    ]

    resources = [
          "${aws_ecr_repository.ecr_repository.arn}*"
      ]
  }
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "s3:*",
    ]
    resources = [
      "${aws_s3_bucket.deployment_pipeline_artifacts.arn}*",
    ]
  }
  statement {
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
    resources = concat(
    [aws_codebuild_project.deployment_docker_image_build.arn, aws_codebuild_project.deployment_gitops_push.arn],
      var.enable_test_stage ? [aws_codebuild_project.deployment_test_code[0].arn] : []
    )
  }
  statement {
    actions = [
      "logs:*",
    ]
    resources = [
      "*"
    ]
  }
  
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      actions = [
        "secretsmanager:GetSecretValue",
      ]
      resources = var.secret_arns
      }
  }
}

resource "aws_iam_role_policy" "deployment_pipeline_role_policy" {
  name   = "${var.name}-deployment-pipeline-iam-role-policy"
  role   = aws_iam_role.deployment_pipeline_role.name
  policy = data.aws_iam_policy_document.deployment_pipeline_policy.json
}

resource "aws_s3_bucket" "deployment_pipeline_artifacts" {
  bucket        = "${data.aws_caller_identity.aws_identity.account_id}-${var.name}-pipeline-data"
  acl           = "private"
  force_destroy = true
}

resource "aws_cloudwatch_log_group" "deployment_docker_image_build_log_group" {
  name              = "${var.name}-deployment-docker-image-build-log-group"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

data "aws_iam_policy_document" "deployment_build_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deployment_build_role" {
  name               = "${var.name}-deployment-build-role"
  assume_role_policy = data.aws_iam_policy_document.deployment_build_assume_role_policy.json
}

data "aws_iam_policy_document" "deployment_build_policy" {
  statement {
    sid = "1"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "${aws_ecr_repository.ecr_repository.arn}*"
    ]
  }
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "logs:*",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "s3:*",
    ]
    resources = [
      "${aws_s3_bucket.deployment_pipeline_artifacts.arn}*",
    ]
  }
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterfacePermission"
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.aws_identity.account_id}:network-interface/*"]
    condition {
      test     = "StringEquals"
      values   = [for subnet_id in var.vpc_private_subnets : "arn:aws:ec2:${data.aws_region.current.name}:${data
      .aws_caller_identity.aws_identity.account_id}:subnet/${subnet_id}"]
      variable = "ec2:Subnet"
    }
    condition {
      test     = "StringEquals"
      values   = ["codebuild.amazonaws.com"]
      variable = "ec2:AuthorizedService"
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      actions = [
        "secretsmanager:GetSecretValue",
      ]
      resources = var.secret_arns
      }
  }
}

resource "aws_iam_role_policy" "deployment_build_role_policy" {
  name   = "${var.name}-deployment-build-backend-role-policy"
  role   = aws_iam_role.deployment_build_role.name
  policy = data.aws_iam_policy_document.deployment_build_policy.json
}

resource "aws_codebuild_project" "deployment_docker_image_build" {
  vpc_config {
    security_group_ids = [
      var.default_security_group_id]
    subnets = var.vpc_private_subnets
    vpc_id  = var.vpc_id
  }
  name           = "${var.name}-deployment-build"
  description    = "Builds docker images for ${var.name}"
  build_timeout  = 20
  service_role   = aws_iam_role.deployment_build_role.arn
  encryption_key = data.aws_kms_alias.s3kmskey.arn

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.deployment_docker_image_build_log_group.name
    }
  }

  artifacts {
    type = "CODEPIPELINE"
  }
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }
  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/docker:18.09.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }
  source {
    type                = "CODEPIPELINE"
    buildspec           = var.buildspec
    report_build_status = false
  }
}

resource "aws_ssm_parameter" "github_webhook_codepipeline_secret" {
  name        = "/${var.name}/github/webhook/deployment-pipeline"
  description = "used by the CICD pipeline to create/destroy github webhooks"
  type        = "SecureString"
  value       = var.github_access_token
}

resource "aws_cloudwatch_log_group" "deployment_test_code_log_group" {
  count = var.enable_test_stage ? 1 : 0
  name              = "${var.name}-deployment-test-code-log-group"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

resource "aws_codebuild_project" "deployment_test_code" {
  count = var.enable_test_stage ? 1 : 0
  name           = "${var.name}-deployment-test-code"
  description    = "Tests for ${var.name}"
  build_timeout  = 20
  service_role   = aws_iam_role.deployment_build_role.arn
  encryption_key = data.aws_kms_alias.s3kmskey.arn

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.deployment_test_code_log_group[0].name
    }
  }

  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }
  source {
    type                = "CODEPIPELINE"
    buildspec           = var.buildspec_test_code
    report_build_status = false
  }
}


resource "aws_cloudwatch_log_group" "deployment_gitops_push_log_group" {
  name              = "${var.name}-deployment-gitops-push-log-group"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

data "aws_iam_policy_document" "deployment_gitops_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deployment_gitops_role" {
  name               = "${var.name}-deployment-gitops-role"
  assume_role_policy = data.aws_iam_policy_document.deployment_gitops_assume_role_policy.json
}

data "aws_iam_policy_document" "deployment_gitops_policy" {
  statement {
    sid = "1"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "${aws_ecr_repository.ecr_repository.arn}*"
    ]
  }
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "logs:*",
    ]
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "s3:*",
    ]
    resources = [
      "${aws_s3_bucket.deployment_pipeline_artifacts.arn}*",
    ]
  }
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs"
    ]
    resources = [
      "*"
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterfacePermission"
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.aws_identity.account_id}:network-interface/*"]
    condition {
      test     = "StringEquals"
      values   = [for subnet_id in var.vpc_private_subnets : "arn:aws:ec2:${data.aws_region.current.name}:${data
      .aws_caller_identity.aws_identity.account_id}:subnet/${subnet_id}"]
      variable = "ec2:Subnet"
    }
    condition {
      test     = "StringEquals"
      values   = ["codebuild.amazonaws.com"]
      variable = "ec2:AuthorizedService"
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      actions = [
        "secretsmanager:GetSecretValue",
      ]
      resources = var.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "deployment_gitops_role_policy" {
  name   = "${var.name}-deployment-gitops-backend-role-policy"
  role   = aws_iam_role.deployment_gitops_role.name
  policy = data.aws_iam_policy_document.deployment_gitops_policy.json
}

resource "aws_codebuild_project" "deployment_gitops_push" {
  vpc_config {
    security_group_ids = [
      var.default_security_group_id]
    subnets = var.vpc_private_subnets
    vpc_id  = var.vpc_id
  }
  name           = "${var.name}-deployment-gitops"
  description    = "Builds docker images for ${var.name}"
  build_timeout  = 20
  service_role   = aws_iam_role.deployment_gitops_role.arn
  encryption_key = data.aws_kms_alias.s3kmskey.arn

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.deployment_gitops_push_log_group.name
    }
  }

  artifacts {
    type = "CODEPIPELINE"
  }
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }
  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/docker:18.09.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    environment_variable {
      name  = "GITHUB_USER"
      type  = "PLAINTEXT"
      value = var.github_user
    }
    environment_variable {
      name  = "GITHUB_ORG"
      type  = "PLAINTEXT"
      value = var.github_organization_name
    }
    environment_variable {
      name  = "DEVOPS_WEBHOOK_URL"
      type  = "PLAINTEXT"
      value = var.devops_slack_webhook
    }
    environment_variable {
      name  = "GITHUB_TOKEN"
      type  = "SECRETS_MANAGER"
      value = var.github_access_token_secret_name
    }
    environment_variable {
      name  = "GITHUB_PASSWORD"
      type  = "SECRETS_MANAGER"
      value = var.github_access_token_secret_name
    }
    environment_variable {
      name  = "TARGET_GITOPS_REPOSITORY"
      type  = "PLAINTEXT"
      value = var.target_gitops_repository
    }
  }
  source {
    type                = "CODEPIPELINE"
    buildspec           = <<EOF
version: 0.2
phases:
  install:
    commands:
    - apt-get -y update
    - apt-get -y install git tar xsel jq
    - wget https://github.com/mikefarah/yq/releases/download/v4.25.3/yq_linux_386 -O /usr/bin/yq && chmod +x /usr/bin/yq
    - wget https://github.com/github/hub/releases/download/v2.14.2/hub-linux-amd64-2.14.2.tgz
    - tar -xzf hub-linux-amd64-2.14.2.tgz
    - cd hub-linux-amd64-2.14.2
    - ./install
  build:
    commands:
    - cd $CODEBUILD_SRC_DIR
    - git config --global hub.protocol https
    - git config --global credential.helper 'store'
    - git config --global user.email '<>'
    - git config --global user.name $GITHUB_USER
    - echo "https://$GITHUB_USER:$GITHUB_PASSWORD@github.com" > ~/.git-credentials
    - hub clone $GITHUB_ORG/$TARGET_GITOPS_REPOSITORY
    - cd $TARGET_GITOPS_REPOSITORY
    - |
      export IMAGE_NAME=$(cat $CODEBUILD_SRC_DIR/build.json | jq .RepositoryUri | tr -d '"')
      export IMAGE_TAG=$(cat $CODEBUILD_SRC_DIR/build.json | jq .Tag | tr -d '"')

      IMAGE_EXISTS=$(yq "contains({\"images\": [{\"name\": \"$IMAGE_NAME\"}]})" kustomization/kustomization.yaml)

      if [ "$IMAGE_EXISTS" = "true" ]
      then
        yq -i "(.images[] | select(.name==\"$IMAGE_NAME\") | .newTag) = \"$IMAGE_TAG\"" kustomization/kustomization.yaml
      else
        yq -i "(.images = .images + [{\"name\": \"$IMAGE_NAME\", \"newTag\": \"$IMAGE_TAG\"}])" kustomization/kustomization.yaml
      fi
    - git add kustomization/kustomization.yaml
    - git commit -m "Updating kustomization/kustomization.yml with value $IMAGE_NAME/$IMAGE_TAG"
    - git push origin master
    - |
      COMMIT_URL=https://github.com/$GITHUB_ORG/$TARGET_GITOPS_REPOSITORY/commit/$CODEBUILD_RESOLVED_SOURCE_VERSION
      curl -X POST -H "Content-type: application/json" --data "{\"text\":\"New image value has been pushed to $TARGET_GITOPS_REPOSITORY gitops repository \"$TARGET_GITOPS_REPOSITORY\": $IMAGE_NAME:$IMAGE_TAG\, \[see commit\]\($COMMIT_URL\)."}" $DEVOPS_WEBHOOK_URL
EOF
  report_build_status = false
  }
}

resource "aws_codepipeline" "deployment_pipeline" {
  name     = var.name
  role_arn = aws_iam_role.deployment_pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.deployment_pipeline_artifacts.bucket
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.s3kmskey.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"
    action {
      name     = "DownloadSource"
      category = "Source"
      configuration = {
        Branch               = var.github_repository_branch
        Owner                = var.github_organization_name
        PollForSourceChanges = false
        Repo                 = var.github_repository_name
        OAuthToken           = var.github_access_token
      }
      output_artifacts = [
        "SourceCode"]
      owner     = "ThirdParty"
      provider  = "GitHub"
      run_order = 1
      version   = 1
    }
  }

  dynamic "stage" {
    for_each = var.enable_test_stage ? [1] : []
    content {
      name = "Test"
      action {
        category = "Build"
        input_artifacts = [
          "SourceCode"]
        name = var.name
        configuration = {
          ProjectName = aws_codebuild_project.deployment_test_code[0].name
          EnvironmentVariables : jsonencode(concat(var.environment_variables,
          [{
            name : "REPOSITORY_URI",
            value : aws_ecr_repository.ecr_repository.repository_url
          },
            {
              name : "AWS_DEFAULT_REGION",
              value : data.aws_region.current.name
            }]
          )
          )
        }
        owner     = "AWS"
        provider  = "CodeBuild"
        run_order = 2
        version   = 1
      }
    }
  }
  
  stage {
    name = "BuildImage"
    action {
      category = "Build"
      input_artifacts = [
        "SourceCode"]
      name = var.name
      output_artifacts = [
        "build-metadata"]
      owner = "AWS"
      configuration = {
        ProjectName = aws_codebuild_project.deployment_docker_image_build.name
        EnvironmentVariables : jsonencode(concat(var.environment_variables,
        [{
          name : "REPOSITORY_URI",
          type : "PLAINTEXT",
          value : aws_ecr_repository.ecr_repository.repository_url
        },
        {
          name : "AWS_DEFAULT_REGION",
          type : "PLAINTEXT",
          value : data.aws_region.current.name
        }]
        )
        )
      }
      provider  = "CodeBuild"
      run_order = 3
      version   = 1
    }
  }

  stage {
    name = "PushToGitOps"
    action {
      category = "Build"
      input_artifacts = [
        "build-metadata"]
      name = var.name
      output_artifacts = []
      owner = "AWS"
      configuration = {
        ProjectName = aws_codebuild_project.deployment_gitops_push.name
      }
      provider  = "CodeBuild"
      run_order = 3
      version   = 1
    }
  }
}

module "deployment_pipeline_notifications" {
  source        = "github.com/kjagiello/terraform-aws-codepipeline-slack-notifications?ref=v1.1.6"
  name          = var.name
  namespace     = ""
  stage         = ""
  slack_url     = var.devops_slack_webhook
  slack_channel = var.devops_slack_channel_name
  codepipelines = [aws_codepipeline.deployment_pipeline]
}