# terraform_ecs

Terraform for running a containerised app on ECS Fargate behind an Application
Load Balancer. Everything is created from scratch: VPC, subnets, NAT gateways,
security groups, network ACLs, the ALB, the ECS cluster and service, the task
execution role, and a CloudWatch log group.

By default it deploys `nginx:latest` on port 80 across three tasks in
`us-west-2`, which is enough to prove the stack works end to end.

## What gets created

- VPC `172.17.0.0/16` with `az_count` public and `az_count` private subnets,
  one per availability zone, carved out with `cidrsubnet`.
- Internet gateway and a public route, plus a NAT gateway and Elastic IP per
  AZ so private subnets can reach the internet.
- One route table per private subnet, explicitly associated.
- Network ACLs on both the public and private subnets, restricting traffic to
  the app port, 443, and ephemeral ports.
- Two security groups: one for the ALB (open on `app_port`), one for the ECS
  tasks (inbound only from the ALB).
- ALB in the public subnets, with an IP-type target group and an HTTP listener
  on `app_port`.
- ECS cluster, Fargate task definition rendered from
  `templates/ecs/myapp.json.tpl`, and a service in the private subnets.
- IAM task execution role with `AmazonECSTaskExecutionRolePolicy` attached.
- CloudWatch log group `/ecs/myapp` retaining 30 days, with a log stream.

```
Internet
   │
   ├── IGW ── ALB (public subnets, :80)
   │            │  target group (ip)
   │            ▼
   │        ECS service ── Fargate tasks (private subnets)
   │            │
   │            └── awslogs → /ecs/myapp
   │
   └── NAT gateways (one per AZ) ← private subnet egress
```

## Usage

```bash
git clone https://github.com/adityapidikiti/terraform_ecs.git
cd terraform_ecs
terraform init
terraform plan
terraform apply
```

`provider.tf` reads the credentials from two variables, so Terraform prompts
for them if they are not set:

```bash
export TF_VAR_AWS_ACCESS_KEY=...
export TF_VAR_AWS_SECRET_KEY=...
export TF_VAR_aws_region=us-west-2
```

Once applied, the ALB hostname is printed:

```bash
terraform output alb_hostname
```

Give the service a minute or two to register tasks with the target group before
the hostname responds.

Tear everything down with:

```bash
terraform destroy
```

## Deploying something other than nginx

Point `app_image` at your image and set `app_port` to the port it listens on:

```bash
terraform apply \
  -var 'app_image=123456789012.dkr.ecr.us-west-2.amazonaws.com/myapp:1.0' \
  -var 'app_count=2'
```

The image has to be reachable from Fargate. For a private ECR repository, add
the `AmazonEC2ContainerRegistryReadOnly` policy to the task execution role.
The container name in the task definition is hard-coded to `myapp`; if you
change it in the template, change `container_name` in `ecs.tf` to match.

If the container listens on a port other than 80, you have to change
`aws_alb_target_group.app.port` in `alb.tf` as well as `app_port`. The target
group port is hard-coded to 80, so the listener would otherwise forward to a
port nothing is listening on and every health check would fail.

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `AWS_ACCESS_KEY` | AWS access key | none, required |
| `AWS_SECRET_KEY` | AWS secret key | none, required |
| `aws_region` | Region to create everything in | `us-west-2` |
| `aws_vpc_cidr` | CIDR block for the VPC | `172.17.0.0/16` |
| `az_count` | Number of AZs to spread across | `2` |
| `app_image` | Docker image to run | `nginx:latest` |
| `app_port` | Port the container listens on, and the ALB listener port | `80` |
| `app_count` | Number of tasks the service runs | `3` |
| `health_check_path` | Path the target group health check requests | `/` |
| `fargate_cpu` | CPU units per task (1024 = 1 vCPU) | `256` |
| `fargate_memory` | Memory per task, in MiB | `512` |
| `ecs_task_execution_role_name` | Name of the task execution role | `myEcsTaskExecutionRole` |

## Outputs

| Name | Description |
|------|-------------|
| `alb_hostname` | DNS name of the load balancer |

## Layout

| File | Contents |
|------|----------|
| `provider.tf` | AWS provider and credentials |
| `variables.tf` | All inputs |
| `network.tf` | VPC, subnets, gateways, route tables |
| `security.tf` | Security groups and network ACLs |
| `alb.tf` | Load balancer, target group, listener |
| `ecs.tf` | Cluster, task definition, service |
| `roles.tf` | Task execution role and policy attachment |
| `logs.tf` | CloudWatch log group and stream |
| `outputs.tf` | ALB hostname |
| `templates/ecs/myapp.json.tpl` | Container definition template |

## Known limitations

This is a demo stack, not something to point at production traffic as-is.

- Credentials are passed as Terraform variables and written into the provider
  block. Prefer the ambient chain (environment variables, shared config, SSO or
  an instance role) and drop `access_key`/`secret_key` from `provider.tf`.
  The variables are not marked `sensitive`, so their values appear in plan
  output.
- There is no `terraform` block pinning a provider version. Recent AWS
  provider releases have removed or renamed several things this code uses:
  - `aws_eip.gw` sets `vpc = true`, which is deprecated in provider 5.x and
    removed in 6.x.
  - `aws_alb` and `aws_alb_target_group` are deprecated aliases for `aws_lb`
    and `aws_lb_target_group`.
- The ALB security group accepts traffic from `0.0.0.0/0` on `app_port`. Fine
  for a demo, but narrow it for anything real.
- `aws_alb_target_group.app` hard-codes `port = 80`, while the listener and
  container definition use `app_port`. Changing `app_port` alone moves the
  listener but leaves the target group pointing at port 80.
- The service sets `assign_public_ip = true` while running in private subnets
  that already have NAT gateways, so tasks get public IPs they do not need.
  Set it to `false` for the usual private-subnet pattern.
- Two NAT gateways are created by default. They are the main recurring cost in
  this stack.
- No HTTPS listener or certificate. Traffic to the ALB is plain HTTP.
- No remote state backend, so state lives in the working directory unless you
  add one.
