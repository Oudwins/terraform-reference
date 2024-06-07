// VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = merge({ "Name" = "${local.tags.Project}-main" }, local.tags)
}


// Gateways
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge({ "Name" = "${local.tags.Project}-main" }, local.tags)
}

resource "aws_eip" "nat-eip" {
  #   domain = "vpc"
  vpc = true // depricated

  tags = merge({ "Name" = "${local.tags.Project}-nat-eip" }, local.tags)
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat-eip.id
  subnet_id     = aws_subnet.public-subnets[local.azs[0]].id

  tags = merge({ "Name" = "${local.tags.Project}" }, local.tags)

  depends_on = [aws_internet_gateway.main]
}

// Subnets

resource "aws_subnet" "private-subnets" {
  for_each          = { for idx, az in local.azs : az => idx }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value)
  availability_zone = each.key

  tags = merge({ "Name" = "${local.tags.Project}-private" }, local.tags)
}


resource "aws_subnet" "public-subnets" {
  for_each          = { for idx, az in local.azs : az => idx }
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value + length(local.azs))
  availability_zone = each.key

  tags = merge({ "Name" = "${local.tags.Project}-private" }, local.tags)
}


// route tables

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge({ "Name" = "${local.tags.Project}-private" }, local.tags)
}

resource "aws_route_table_association" "private-ass" {
  for_each       = aws_subnet.private-subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge({ "Name" = "${local.tags.Project}-public" }, local.tags)
}

resource "aws_route_table_association" "public-ass" {
  for_each       = aws_subnet.public-subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id

}
