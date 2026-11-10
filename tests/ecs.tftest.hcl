# Plan-level tests for the root configuration. The AWS provider is mocked, so
# nothing is created and no credentials are needed.
#   terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.main.name == "myapp-cluster"
    error_message = "Cluster name should be derived from name_prefix."
  }

  assert {
    condition     = aws_ecs_service.main.name == "myapp-service"
    error_message = "Service name should be derived from name_prefix."
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/ecs/myapp"
    error_message = "Log group should be /ecs/<name_prefix>."
  }

  assert {
    condition     = aws_lb_target_group.app.port == 80
    error_message = "Target group port should follow app_port."
  }

  assert {
    condition     = length(aws_nat_gateway.gw) == 2
    error_message = "One NAT gateway per AZ by default."
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "No HTTPS listener should exist without a certificate."
  }
}

run "target_group_port_follows_app_port" {
  command = plan

  variables {
    app_port      = 8080
    listener_port = 8080
  }

  assert {
    condition     = aws_lb_target_group.app.port == 8080
    error_message = "The target group must use app_port, not a hardcoded 80."
  }

  assert {
    condition     = one([for lb in aws_ecs_service.main.load_balancer : lb.container_port]) == 8080
    error_message = "The service should register the container on app_port."
  }
}

run "https_when_certificate_supplied" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/abc-123"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "Supplying a certificate should create an HTTPS listener."
  }

  assert {
    condition     = aws_lb_listener.https[0].port == 443
    error_message = "The HTTPS listener should bind 443."
  }

  assert {
    condition     = one([for a in aws_lb_listener.http.default_action : a.type]) == "redirect"
    error_message = "The HTTP listener should redirect when HTTPS is enabled."
  }
}

run "container_definition_defaults" {
  command = plan

  variables {
    environment_variables = {
      LOG_LEVEL = "info"
    }
    container_command = ["nginx", "-g", "daemon off;"]
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].name == "myapp"
    error_message = "Container name should match name_prefix."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Root filesystem should be read-only by default."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment[0].name == "LOG_LEVEL"
    error_message = "Environment variables should reach the container definition."
  }

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.app.container_definitions)[0].command) == 3
    error_message = "container_command should override the image CMD."
  }
}

run "secrets_reach_container_and_role" {
  command = plan

  variables {
    secrets = {
      DB_PASSWORD = "arn:aws:secretsmanager:us-west-2:123456789012:secret:db-pass"
    }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].secrets[0].name == "DB_PASSWORD"
    error_message = "Secrets should be passed as container secrets."
  }

  assert {
    condition     = length(aws_iam_role_policy.read_secrets) == 1
    error_message = "The execution role should get a policy granting read access to the secrets."
  }
}

run "no_secrets_policy_when_unused" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.read_secrets) == 0
    error_message = "No secrets policy should be created when secrets is empty."
  }
}

run "exec_adds_ssm_policy" {
  command = plan

  variables {
    enable_exec = true
  }

  assert {
    condition     = aws_ecs_service.main.enable_execute_command == true
    error_message = "enabled_exec should turn on execute-command."
  }

  assert {
    condition     = length(aws_iam_role_policy.exec) == 1
    error_message = "ECS Exec needs SSM permissions on the task role."
  }
}

run "autoscaling_attached" {
  command = plan

  assert {
    condition     = length(aws_appautoscaling_target.ecs) == 1
    error_message = "Autoscaling should be on by default."
  }

  assert {
    condition     = aws_appautoscaling_target.ecs[0].min_capacity == 1
    error_message = "Default minimum capacity is 1."
  }

  assert {
    condition     = aws_appautoscaling_target.ecs[0].max_capacity == 10
    error_message = "Default maximum capacity is 10."
  }
}

run "autoscaling_can_be_disabled" {
  command = plan

  variables {
    enable_autoscaling = false
  }

  assert {
    condition     = length(aws_appautoscaling_target.ecs) == 0
    error_message = "Autoscaling should not be created when disabled."
  }
}

run "container_insights_toggle" {
  command = plan

  variables {
    enable_container_insights = false
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.main.setting : s.value]) == "disabled"
    error_message = "Container Insights should be off when disabled."
  }
}

run "existing_roles" {
  command = plan

  variables {
    create_iam_roles        = false
    task_execution_role_arn = "arn:aws:iam::123456789012:role/existing-exec"
    task_role_arn           = "arn:aws:iam::123456789012:role/existing-task"
  }

  assert {
    condition     = length(aws_iam_role.task_execution) == 0
    error_message = "No roles should be created when create_iam_roles is false."
  }

  assert {
    condition     = aws_ecs_task_definition.app.execution_role_arn == "arn:aws:iam::123456789012:role/existing-exec"
    error_message = "The supplied execution role should be used."
  }

  assert {
    condition     = aws_ecs_task_definition.app.task_role_arn == "arn:aws:iam::123456789012:role/existing-task"
    error_message = "The supplied task role should be used."
  }
}
