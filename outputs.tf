# outputs.tf

output "alb_hostname" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone id of the load balancer, for Route 53 alias records."
  value       = aws_lb.main.zone_id
}

output "url" {
  description = "URL the application is reachable at."
  value       = local.https_enabled ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}:${var.listener_port}"
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.main.name
}

output "task_definition_arn" {
  description = "ARN of the active task definition."
  value       = aws_ecs_task_definition.app.arn
}

output "target_group_arn" {
  description = "ARN of the target group the service registers with."
  value       = aws_lb_target_group.app.arn
}

output "log_group_name" {
  description = "CloudWatch log group receiving container output."
  value       = aws_cloudwatch_log_group.app.name
}

output "vpc_id" {
  description = "Id of the created VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Ids of the private subnets the tasks run in."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Ids of the public subnets the load balancer uses."
  value       = aws_subnet.public[*].id
}

output "task_execution_role_arn" {
  description = "ARN of the role the ECS agent uses, whether created here or supplied."
  value       = local.execution_role_arn
}

output "task_role_arn" {
  description = "ARN of the role the application uses, whether created here or supplied."
  value       = local.task_role_arn
}

output "autoscaling_enabled" {
  description = "Whether the service has a CPU target tracking policy attached."
  value       = var.enable_autoscaling
}
