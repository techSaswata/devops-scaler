# ---------------------------------------------------------------------------
#  NETWORK:  VPC → Subnets → Internet Gateway → Route Tables
# ---------------------------------------------------------------------------

# Look up the AZs available in this region rather than hard-coding names -
# ap-south-1a does not exist in every region, and AZ names are per-account.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Required for instances to get DNS names, and for VPC endpoints to resolve.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ----------------------------- public subnets -----------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # What actually gives instances here a public IP on launch.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "public"
  }
}

# ----------------------------- private subnets ----------------------------
# No NAT Gateway is created: a NAT costs ~$32/month and this demo does not need
# outbound internet from the private tier. The subnets demonstrate the
# segmentation; see the README for the production shape.
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  }
}

# --------------------------- internet gateway -----------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ----------------------------- route tables -------------------------------
# A subnet is "public" ONLY because its route table sends 0.0.0.0/0 to an IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The private route table has NO 0.0.0.0/0 route - only the implicit `local`
# route for traffic inside the VPC. That is what makes it private.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
