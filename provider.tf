# Credentials come from the standard provider chain, so nothing secret lives in
# this file: environment variables, ~/.aws/config, SSO, or an instance role.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
