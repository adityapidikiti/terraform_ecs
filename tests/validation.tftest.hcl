# Guardrails: invalid input must be rejected before anything reaches AWS.
#   terraform test -filter=tests/validation.tftest.hcl

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-west-2a", "us-west-2b", "us-west-2c"]
    }
  }
}

run "rejects_single_az" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "rejects_bad_name_prefix" {
  command = plan

  variables {
    name_prefix = "My_App"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_empty_ingress" {
  command = plan

  variables {
    ingress_cidr_blocks = []
  }

  expect_failures = [var.ingress_cidr_blocks]
}

run "rejects_bad_cpu_target" {
  command = plan

  variables {
    autoscaling_cpu_target = 150
  }

  expect_failures = [var.autoscaling_cpu_target]
}

run "rejects_inverted_autoscaling_bounds" {
  command = plan

  variables {
    autoscaling_min_capacity = 10
    autoscaling_max_capacity = 2
  }

  expect_failures = [aws_ecs_service.main]
}

run "rejects_missing_roles" {
  command = plan

  variables {
    create_iam_roles = false
  }

  expect_failures = [aws_ecs_task_definition.app]
}
