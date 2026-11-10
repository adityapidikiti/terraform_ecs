# logs.tf

# The awslogs driver creates streams inside this group on its own, so there is
# no static stream resource to manage.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_in_days

  tags = { Name = "${var.name_prefix}-logs" }
}
