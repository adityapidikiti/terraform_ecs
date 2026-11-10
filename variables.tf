variable "aws_region" {
  type        = string
  description = "Region everything is created in."
  default     = "us-west-2"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for created resource names. Must be lower case alphanumeric or hyphens."
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.name_prefix))
    error_message = "name_prefix must start with a letter or digit, and be at most 21 characters of lower case letters, digits and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource through the provider's default_tags."
  default     = {}
}

# Network

variable "aws_vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "172.17.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to spread across. Creates one public and one private subnet per AZ."
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 so the load balancer can span multiple zones."
  }
}

# Application

variable "app_image" {
  type        = string
  description = "Container image to run."
  default     = "nginx:latest"
}

variable "app_port" {
  type        = number
  description = "Port the container listens on. The target group and container definition both use it."
  default     = 80
}

variable "app_count" {
  type        = number
  description = "Desired number of running tasks. Ignored as a diff source when autoscaling is enabled."
  default     = 3
}

variable "container_command" {
  type        = list(string)
  description = "Override the image CMD. Empty uses the image default."
  default     = []
}

variable "environment_variables" {
  type        = map(string)
  description = "Plain environment variables passed to the container."
  default     = {}
}

variable "secrets" {
  type        = map(string)
  description = "Environment variables sourced from SSM Parameter Store or Secrets Manager, mapped as name => ARN. The execution role is granted read access."
  default     = {}
}

variable "readonly_root_filesystem" {
  type        = bool
  description = "Mount the container root filesystem read-only. Recommended, but the image must write only to /tmp."
  default     = true
}

variable "health_check_path" {
  type        = string
  description = "Path the target group health check requests."
  default     = "/"
}

variable "fargate_cpu" {
  type        = string
  description = "CPU units per task. 1024 units is one vCPU."
  default     = "256"
}

variable "fargate_memory" {
  type        = string
  description = "Memory per task in MiB."
  default     = "512"
}

variable "assign_public_ip" {
  type        = bool
  description = "Give tasks public IPs. Not needed with NAT gateways; leave false for private subnets."
  default     = false
}

# Load balancer

variable "listener_port" {
  type        = number
  description = "Port the HTTP listener binds to. With a certificate it redirects to 443 instead of forwarding."
  default     = 80
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN. When set, the load balancer serves HTTPS on 443 and redirects HTTP to it."
  default     = null
}

variable "ingress_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the load balancer."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.ingress_cidr_blocks) > 0
    error_message = "ingress_cidr_blocks cannot be empty."
  }
}

variable "health_check_grace_period" {
  type        = number
  description = "Seconds the service ignores failing health checks after a task starts."
  default     = 60
}

# Platform features

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights on the cluster."
  default     = true
}

variable "enable_exec" {
  type        = bool
  description = "Enable ECS Exec for shell access into running tasks. Adds SSM permissions to the task role."
  default     = false
}

variable "enable_autoscaling" {
  type        = bool
  description = "Scale the service on average CPU utilisation."
  default     = true
}

variable "autoscaling_min_capacity" {
  type        = number
  description = "Minimum task count when autoscaling is enabled."
  default     = 1
}

variable "autoscaling_max_capacity" {
  type        = number
  description = "Maximum task count when autoscaling is enabled."
  default     = 10
}

variable "autoscaling_cpu_target" {
  type        = number
  description = "Target average CPU utilisation percentage."
  default     = 70

  validation {
    condition     = var.autoscaling_cpu_target > 0 && var.autoscaling_cpu_target <= 100
    error_message = "autoscaling_cpu_target must be between 1 and 100."
  }
}

variable "enable_deployment_circuit_breaker" {
  type        = bool
  description = "Roll back automatically when a deployment fails to stabilise."
  default     = true
}

# IAM

variable "task_execution_role_name" {
  type        = string
  description = "Name for the task execution role. Used only when create_iam_roles is true."
  default     = null
}

variable "create_iam_roles" {
  type        = bool
  description = "Create the execution and task roles. Set false and supply ARNs to use existing ones."
  default     = true
}

variable "task_execution_role_arn" {
  type        = string
  description = "Existing execution role ARN. Required when create_iam_roles is false."
  default     = null
}

variable "task_role_arn" {
  type        = string
  description = "Existing task role ARN. Required when create_iam_roles is false."
  default     = null
}

variable "log_retention_in_days" {
  type        = number
  description = "Retention for the container log group."
  default     = 30
}
