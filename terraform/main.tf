## ECR Resource
resource "aws_ecr_repository" "ecr" {
  name = "example-repo"
}

## IAM Role
resource "aws_iam_role" "role-codebuild" {
  name               = "example-codebuild"
  assume_role_policy = "${file("./role/codebuild_assume_role.json")}"
}

resource "aws_iam_role" "role-codedeploy" {
  name               = "example-codedeploy"
  assume_role_policy = "${file("./role/codedeploy_assume_role.json")}"
}

resource "aws_iam_role" "role-ecs-task" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${file("./role/ecs_task_assume_role.json")}"
}

## IAM Role Policy
resource "aws_iam_role_policy" "policy-codebuild" {
  name   = "build-policy"
  role   = "${aws_iam_role.role-codebuild.name}"
  policy = "${file("./role/codebuild_build_policy.json")}"
}

resource "aws_iam_role_policy" "policy-codedeploy" {
  name   = "deploy-policy"
  role   = "${aws_iam_role.role-codedeploy.name}"
  policy = "${file("./role/codedeploy_deploy_policy.json")}"
}

resource "aws_iam_role_policy" "policy-ecs-task" {
  name   = "task-policy"
  role   = "${aws_iam_role.role-ecs-task.name}"
  policy = "${file("./role/ecs_task_policy.json")}"
}

## Security Group
resource "aws_security_group" "alb-sg" {
  name        = "example-alb-sg"
  description = "example-alb-sg"
}

## Security Group
resource "aws_security_group" "fargate-sg" {
  name        = "fargate-sg"
  description = "fargate-sg"
}

## Security Group Rule
resource "aws_security_group_rule" "inbound-http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.alb-sg.id}"
}

resource "aws_security_group_rule" "outbound-all" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  from_port         = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.alb-sg.id}"
}

resource "aws_security_group_rule" "inbound-http-fargate" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.fargate-sg.id}"
}

resource "aws_security_group_rule" "outbound-all-fargate" {
  type              = "egress"
  to_port           = 0
  protocol          = "-1"
  from_port         = 0
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.fargate-sg.id}"
}

## ALB
resource "aws_alb" "alb" {
  name            = "example"
  security_groups = ["${aws_security_group.alb-sg.id}"]
  subnets         = "${var.subnets}"
}

## Target Group
resource "aws_alb_target_group" "target_group1" {
  name        = "example-tg1"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${var.vpc_id}"
}

resource "aws_alb_target_group" "target_group2" {
  name        = "example-tg2"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${var.vpc_id}"
}

## Listener
resource "aws_alb_listener" "listener" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.target_group1.arn}"
    type             = "forward"
  }
}

## CodeBuild
resource "aws_codebuild_project" "codebuild" {
  name         = "example"
  service_role = "${aws_iam_role.role-codebuild.arn}"

  source {
    type            = "GITHUB"
    location        = "https://github.com/nezumisannn/aws-fargate-pipeline-example.git"
    git_clone_depth = 1
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:1.0-1.8.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    type                        = "LINUX_CONTAINER"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }
}

## ECS Cluster
resource "aws_ecs_cluster" "ecs-cluster" {
  name = "cluster-example"
}

## ECS Task Definition
resource "aws_ecs_task_definition" "ecs-task" {
  family                = "task-example"
  container_definitions = "${file("task/task_definition.json")}"
  cpu                   = "256"
  memory                = "512"
  execution_role_arn    = "${aws_iam_role.role-ecs-task.arn}"
  requires_compatibilities = [
    "FARGATE"
  ]
}

## ECS Service
resource "aws_ecs_service" "ecs-service" {
  name                              = "service-nginx"
  cluster                           = "${aws_ecs_cluster.ecs-cluster.id}"
  task_definition                   = "${aws_ecs_task_definition.ecs-task.arn}"
  launch_type                       = "FARGATE"
  desired_count                     = 3
  health_check_grace_period_seconds = 0

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  load_balancer {
    container_name   = "nginx-web"
    container_port   = "80"
    target_group_arn = "${aws_alb_target_group.target_group1.arn}"
  }

  network_configuration {
    assign_public_ip = true
    security_groups = [
      "${aws_security_group.fargate-sg.id}"
    ]
    subnets = "${var.subnets}"
  }
}

## CodeDeploy APP
resource "aws_codedeploy_app" "codedeploy-app" {
  compute_platform = "ECS"
  name             = "AppECS-cluster-example-service-nginx"
}

resource "aws_codedeploy_deployment_group" "codedeploy-group" {
  app_name               = "${aws_codedeploy_app.codedeploy-app.name}"
  service_role_arn       = "${aws_iam_role.role-codedeploy.arn}"
  deployment_group_name  = "DgpECS-cluster-example-service-nginx"
  deployment_config_name = "CodeDeployDefault.OneAtATime"

  ecs_service {
    cluster_name = "${aws_ecs_cluster.ecs-cluster.name}"
    service_name = "${aws_ecs_service.ecs-service.name}"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 0
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [
          "${aws_alb_listener.listener.arn}"
        ]
      }
      target_group {
        name = "${aws_alb_target_group.target_group1.arn}"
      }
      target_group {
        name = "${aws_alb_target_group.target_group2.arn}"
      }
    }
  }
}

## CodePipeline
resource "aws_codepipeline" "codepipeline" {
  name     = "example-pipeline"
  role_arn = "XXXXXXXXXXXX"

  artifact_store {
    location = "XXXXXXXXXXXX"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      category = "Source"
      configuration = {
        "Branch"               = "master"
        "Owner"                = "XXXXXXXXXX"
        "PollForSourceChanges" = "false"
        "Repo"                 = "XXXXXXXXXX"
      }
      input_artifacts = []
      name            = "Source"
      output_artifacts = [
        "SourceArtifact",
      ]
      owner     = "ThirdParty"
      provider  = "GitHub"
      run_order = 1
      version   = "1"
    }
  }
  stage {
    name = "Build"

    action {
      category = "Build"
      configuration = {
        "ProjectName" = "${aws_codebuild_project.codebuild.name}"
      }
      input_artifacts = [
        "SourceArtifact",
      ]
      name = "Build"
      output_artifacts = [
        "BuildArtifact",
      ]
      owner     = "AWS"
      provider  = "CodeBuild"
      run_order = 1
      version   = "1"
    }
  }
  stage {
    name = "Deploy"

    action {
      category = "Deploy"
      configuration = {
        "AppSpecTemplateArtifact"        = "SourceArtifact"
        "ApplicationName"                = "${aws_codedeploy_app.codedeploy-app.name}"
        "DeploymentGroupName"            = "${aws_codedeploy_deployment_group.codedeploy-group.name}"
        "Image1ArtifactName"             = "BuildArtifact"
        "Image1ContainerName"            = "IMAGE1_NAME"
        "TaskDefinitionTemplateArtifact" = "SourceArtifact"
      }
      input_artifacts = [
        "BuildArtifact",
        "SourceArtifact",
      ]
      name             = "Deploy"
      output_artifacts = []
      owner            = "AWS"
      provider         = "CodeDeployToECS"
      run_order        = 1
      version          = "1"
    }
  }
}

## Webhook Secret
locals {
  webhook_secret = "XXXXXXXXXXXXXXXXXXXXXX"
}

## CodePipeline Webhook
resource "aws_codepipeline_webhook" "codepipeline-webhook" {
  name            = "webhook-github"
  authentication  = "GITHUB_HMAC"
  target_action   = "Source"
  target_pipeline = "${aws_codepipeline.codepipeline.name}"

  authentication_configuration {
    secret_token = "${local.webhook_secret}"
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

## Github Webhook
resource "github_repository_webhook" "repository-webhook" {
  repository = "aws-pipeline-example"

  name = "codepipeline-webhook"

  configuration {
    url          = "${aws_codepipeline_webhook.codepipeline-webhook.url}"
    content_type = "json"
    insecure_ssl = true
    secret       = "${local.webhook_secret}"
  }

  events = ["push"]
}
