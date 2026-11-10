# terraform_ecs

Terraform for running a containerised app on ECS Fargate behind an Application
Load Balancer. Everything is created from scratch: VPC, subnets, NAT gateways,
security groups, network ACLs, the load balancer, the ECS cluster and service,
IAM roles, and a CloudWatch log group.

By default it deploys `nginx:latest` on port 80 across three tasks in
`us-west-2`, behind plain HTTP, which is enough to prove the stack works end to
end.

```
Internet
   │
   ├── IGW ── ALB (public subnets)  HTTP:80 → redirect if HTTPS is on
   │            │  target group :app_port
   │            ▼
   │        ECS service ── Fargate tasks (private subnets)
   │            │   ├── awslogs → /ecs/<prefix>
   │            │   └── autoscaling on average CPU
   │            │
   │            └── NAT gateways (one per AZ) → egress
```

## Features

- **Two modes of entry**: HTTP only, or HTTPS with an ACM certificate. Supplying
  `certificate_arn` adds a 443 listener and turns the HTTP listener into a
  redirect. No certificate, no redirect, no surprises.
- **Separate execution and task roles.** The ECS agent gets a role for pulling
  images, writing logs and reading secrets; the application gets its own role.
  Set `create_iam_roles = false` to bring your own.
- **Secrets from SSM or Secrets Manager.** Pass `secrets = { NAME = arn }` and
  the execution role is granted read access to exactly those ARNs.
- **Autoscaling** on average CPU, on by default. `desired_count` stops being a
  diff source once the policy is attached, so Terraform will not fight the
  scaler.
- **Deployment circuit breaker** with automatic rollback when a deployment
  fails to stabilise.
- **ECS Exec**, off by default. Turn it on and the SSM channel permissions are
  added to the task role.
- **Container Insights** on the cluster, on by default.
- **Read-only root filesystem** for the container, on by default.
- **One NAT gateway per AZ**, each with its own route table, so a zone failure
  does not break egress for the other zones.

## Usage

```bash
git clone https://github.com/adityapidikiti/terraform_ecs.git
cd terraform_ecs
terraform init
terraform apply
```

Credentials come from the standard AWS provider chain, which means environment
variables, `~/.aws/config`, SSO, or an instance role. Nothing secret is declared
in this repository.

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
terraform apply
```

Once applied:

```bash
terraform output url
terraform output alb_hostname
```

Give the service a minute to register tasks with the target group before the
hostname responds.

Tear down with `terraform destroy`. The NAT gateways and load balancer are the
line items that cost money while it runs.

## Common changes

Deploy a different image:

```bash
terraform apply \
  -var 'app_image=123456789012.dkr.ecr.us-west-2.amazonaws.com/myapp:1.0' \
  -var 'app_port=8080' \
  -var 'listener_port=8080'
```

The target group follows `app_port`, and the listener follows `listener_port`,
so they can differ. If they do, keep the security groups in mind: the load
balancer opens `listener_port` and 443, and the tasks open `app_port` to the
load balancer only.

Add HTTPS:

```bash
terraform apply \
  -var 'certificate_arn=arn:aws:acm:us-west-2:123456789012:certificate/abc-123'
```

Traffic on port 80 then returns a 301 to HTTPS.

Read a secret from Secrets Manager:

```hcl
secrets = {
  DB_PASSWORD = "arn:aws:secretsmanager:us-west-2:123456789012:secret:db-pass"
}
```

The variable name becomes the environment variable name inside the container.

Shell into a running task:

```bash
terraform apply -var 'enable_exec=true'
aws ecs execute-command \
  --cluster myapp-cluster \
  --task "$(aws ecs list-tasks --cluster myapp-cluster --query 'taskArns[0]' --output text)" \
  --container myapp \
  --interactive \
  --command /bin/sh
```

The image needs a shell for this to be useful.

Lock the load balancer down to an office range:

```hcl
ingress_cidr_blocks = ["203.0.113.0/24"]
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `aws_region` | Region everything is created in | `us-west-2` |
| `name_prefix` | Prefix for resource names | `myapp` |
| `tags` | Tags applied to every resource | `{}` |
| `aws_vpc_cidr` | VPC CIDR block | `172.17.0.0/16` |
| `az_count` | AZs to spread across, minimum 2 | `2` |
| `app_image` | Container image | `nginx:latest` |
| `app_port` | Port the container listens on | `80` |
| `app_count` | Desired task count | `3` |
| `container_command` | Override the image CMD | `[]` |
| `environment_variables` | Plain environment variables | `{}` |
| `secrets` | name to ARN map, read by the execution role | `{}` |
| `readonly_root_filesystem` | Mount the root filesystem read-only | `true` |
| `health_check_path` | Target group health check path | `/` |
| `fargate_cpu` | CPU units per task | `256` |
| `fargate_memory` | Memory per task in MiB | `512` |
| `assign_public_ip` | Give tasks public IPs | `false` |
| `listener_port` | HTTP listener port | `80` |
| `certificate_arn` | ACM certificate, enables HTTPS | `null` |
| `ingress_cidr_blocks` | Who may reach the load balancer | `["0.0.0.0/0"]` |
| `health_check_grace_period` | Seconds before health checks count | `60` |
| `enable_container_insights` | CloudWatch Container Insights | `true` |
| `enable_exec` | ECS Exec shell access | `false` |
| `enable_autoscaling` | CPU target tracking | `true` |
| `autoscaling_min_capacity` | Minimum tasks | `1` |
| `autoscaling_max_capacity` | Maximum tasks | `10` |
| `autoscaling_cpu_target` | Target average CPU percentage | `70` |
| `enable_deployment_circuit_breaker` | Roll back failed deployments | `true` |
| `create_iam_roles` | Create roles, or use the ARNs below | `true` |
| `task_execution_role_name` | Name for the created execution role | `null` |
| `task_execution_role_arn` | Existing execution role | `null` |
| `task_role_arn` | Existing task role | `null` |
| `log_retention_in_days` | Container log retention | `30` |

## Outputs

| Name | Description |
|------|-------------|
| `alb_hostname` | Public DNS name of the load balancer |
| `alb_zone_id` | Zone id for Route 53 alias records |
| `url` | URL the application is reachable at |
| `cluster_name` | ECS cluster name |
| `service_name` | ECS service name |
| `task_definition_arn` | ARN of the active task definition |
| `target_group_arn` | ARN of the target group |
| `log_group_name` | CloudWatch log group |
| `vpc_id` | VPC id |
| `private_subnet_ids` | Subnets the tasks run in |
| `public_subnet_ids` | Subnets the load balancer uses |
| `task_execution_role_arn` | Effective execution role ARN |
| `task_role_arn` | Effective task role ARN |
| `autoscaling_enabled` | Whether autoscaling is attached |

## Testing

`tests/` holds Terraform test files that mock the AWS provider, so they need no
credentials and create nothing.

```bash
terraform init
terraform test
```

Seventeen runs: eleven covering the configuration (defaults, target group port,
HTTPS, container definition, secrets, Exec, autoscaling, Insights, existing
roles) and six guardrails checking that invalid input is rejected.

CI runs `terraform fmt -check`, `terraform validate` and `terraform test` on
every push and pull request.

## Layout

| File | Contents |
|------|----------|
| `versions.tf` | Terraform and provider constraints |
| `provider.tf` | AWS provider, credentials from the environment, default tags |
| `variables.tf` | All inputs, with validation |
| `network.tf` | VPC, subnets, gateways, route tables |
| `security.tf` | Security groups and network ACLs |
| `alb.tf` | Load balancer, target group, HTTP and HTTPS listeners |
| `ecs.tf` | Cluster, container definition, task definition, service |
| `autoscaling.tf` | Application Auto Scaling target and CPU policy |
| `roles.tf` | Execution and task roles, secrets and Exec policies |
| `logs.tf` | CloudWatch log group |
| `outputs.tf` | URLs, names, ARNs, network ids |
| `tests/` | Terraform test files |

## Notes

- The container definition is built with `jsonencode` rather than a template
  file, so conditional keys like `secrets` and `command` are type-checked
  instead of string-interpolated.
- No remote backend is configured. State lives in the working directory unless
  you add one. Two people applying this at once will conflict.
- `fargate_cpu` and `fargate_memory` are passed through as strings because that
  is what the provider expects. Valid pairs are fixed by AWS, for example
  256/512, 512/1024, 1024/2048. An invalid pair is rejected at apply, not at
  plan.
- Task definitions are immutable, so changing the image creates a new revision
  and the service rolls to it. The circuit breaker rolls back if the new
  revision never becomes healthy.
