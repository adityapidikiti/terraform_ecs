# ecs.tf

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

locals {
  container_name = var.name_prefix

  # Built as an object and encoded, rather than interpolated into a template
  # file, so conditional keys like secrets stay type-safe.
  container_definition = merge(
    {
      name      = local.container_name
      image     = var.app_image
      cpu       = tonumber(var.fargate_cpu)
      memory    = tonumber(var.fargate_memory)
      essential = true

      readonlyRootFilesystem = var.readonly_root_filesystem

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for name, value in var.environment_variables : {
          name  = name
          value = value
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    length(var.container_command) > 0 ? { command = var.container_command } : {},
    length(var.secrets) > 0 ? {
      secrets = [
        for name, arn in var.secrets : {
          name      = name
          valueFrom = arn
        }
      ]
    } : {},
  )
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name_prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory

  execution_role_arn = local.execution_role_arn
  task_role_arn      = local.task_role_arn

  container_definitions = jsonencode([local.container_definition])

  tags = { Name = "${var.name_prefix}-task" }

  lifecycle {
    precondition {
      condition     = var.create_iam_roles || (var.task_execution_role_arn != null && var.task_role_arn != null)
      error_message = "create_iam_roles = false requires both task_execution_role_arn and task_role_arn."
    }
  }
}

resource "aws_ecs_service" "main" {
  name            = "${var.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.health_check_grace_period
  enable_execute_command            = var.enable_exec

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = var.app_port
  }

  dynamic "deployment_circuit_breaker" {
    for_each = var.enable_deployment_circuit_breaker ? [1] : []
    content {
      enable   = true
      rollback = true
    }
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.task_execution,
  ]

  lifecycle {
    # The autoscaler owns desired_count once it is attached; without this every
    # plan would try to pull the task count back to var.app_count.
    ignore_changes = [desired_count]

    precondition {
      condition     = !var.enable_autoscaling || var.autoscaling_max_capacity >= var.autoscaling_min_capacity
      error_message = "autoscaling_max_capacity must be greater than or equal to autoscaling_min_capacity."
    }
  }
}
