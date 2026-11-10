# roles.tf
#
# Two distinct roles, which is the part most ECS setups get wrong:
#   execution role - the ECS agent pulls the image, writes logs, reads secrets
#   task role      - the application code calls AWS APIs
# Keeping them apart means a compromised container cannot widen the permissions
# the platform needs in order to start it.

locals {
  # Static documents, so jsonencode is enough. That also keeps them resolvable
  # at plan time, which a policy-document data source is not.
  ecs_tasks_assume_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  read_secrets_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "ssm:GetParameters",
      ]
      Resource = values(var.secrets)
    }]
  })

  exec_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })

  execution_role_arn = var.create_iam_roles ? aws_iam_role.task_execution[0].arn : var.task_execution_role_arn
  task_role_arn      = var.create_iam_roles ? aws_iam_role.task[0].arn : var.task_role_arn
}

resource "aws_iam_role" "task_execution" {
  count = var.create_iam_roles ? 1 : 0

  name               = var.task_execution_role_name != null ? var.task_execution_role_name : "${var.name_prefix}-task-execution"
  assume_role_policy = local.ecs_tasks_assume_policy

  tags = { Name = "${var.name_prefix}-task-execution" }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  count = var.create_iam_roles ? 1 : 0

  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read access for the secrets referenced in the container definition.
resource "aws_iam_role_policy" "read_secrets" {
  count = var.create_iam_roles && length(var.secrets) > 0 ? 1 : 0

  name   = "${var.name_prefix}-read-secrets"
  role   = aws_iam_role.task_execution[0].id
  policy = local.read_secrets_policy
}

resource "aws_iam_role" "task" {
  count = var.create_iam_roles ? 1 : 0

  name               = "${var.name_prefix}-task"
  assume_role_policy = local.ecs_tasks_assume_policy

  tags = { Name = "${var.name_prefix}-task" }
}

# ECS Exec tunnels through SSM, so the task role needs the messages channels.
resource "aws_iam_role_policy" "exec" {
  count = var.create_iam_roles && var.enable_exec ? 1 : 0

  name   = "${var.name_prefix}-exec"
  role   = aws_iam_role.task[0].id
  policy = local.exec_policy
}
