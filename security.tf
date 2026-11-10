# security.tf

# Load balancer: open on the listener port, and on 443 when HTTPS is enabled.
resource "aws_security_group" "lb" {
  name        = "${var.name_prefix}-lb"
  description = "Public access to ${var.name_prefix} load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP listener"
    protocol    = "tcp"
    from_port   = var.listener_port
    to_port     = var.listener_port
    cidr_blocks = var.ingress_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = var.ingress_cidr_blocks
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-lb-sg" }
}

# Tasks accept traffic from the load balancer only.
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-tasks"
  description = "Inbound from the load balancer only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application port from the ALB"
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-tasks-sg" }
}

locals {
  # Ports the NACLs must allow in both directions: the app port, 443 for
  # image pulls and API calls, and the ephemeral range for return traffic.
  nacl_ports = distinct([var.app_port, 443])

  ingress_cidrs = var.ingress_cidr_blocks
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  dynamic "ingress" {
    for_each = local.nacl_ports
    content {
      protocol   = "tcp"
      rule_no    = 100 + ingress.key
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = ingress.value
      to_port    = ingress.value
    }
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  dynamic "egress" {
    for_each = local.nacl_ports
    content {
      protocol   = "tcp"
      rule_no    = 100 + egress.key
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = egress.value
      to_port    = egress.value
    }
  }

  egress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${var.name_prefix}-private-acl" }
}

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  dynamic "ingress" {
    for_each = local.nacl_ports
    content {
      protocol   = "tcp"
      rule_no    = 100 + ingress.key
      action     = "allow"
      cidr_block = "0.0.0.0/0"
      from_port  = ingress.value
      to_port    = ingress.value
    }
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${var.name_prefix}-public-acl" }
}
