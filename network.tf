# network.tf

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# One private subnet per AZ, each in its own /24 inside the VPC range.
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.name_prefix}-private-${count.index}" }
}

# One public subnet per AZ, offset past the private range.
resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-public-${count.index}" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.name_prefix}-igw" }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.main.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# One NAT gateway per AZ so a zone failure does not take out egress for the
# others. This is the largest recurring cost in the stack.
resource "aws_eip" "gw" {
  count  = var.az_count
  domain = "vpc"

  depends_on = [aws_internet_gateway.gw]

  tags = { Name = "${var.name_prefix}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "gw" {
  count         = var.az_count
  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.gw[count.index].id

  depends_on = [aws_internet_gateway.gw]

  tags = { Name = "${var.name_prefix}-nat-${count.index}" }
}

# Each private subnet gets its own route table so its egress stays in-zone.
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw[count.index].id
  }

  tags = { Name = "${var.name_prefix}-private-rt-${count.index}" }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
