# ---------------------------------------------------------------------------
# Slice 02 - VPC, network, and access
# Private network + Session Manager admin path, no public inbound.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "jra-sonarqube-vpc" }
}

# Public subnet: outbound via IGW; instances auto-get a public IP (Option 2:
# SSM + image pulls over the internet; inbound still blocked by security groups).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "jra-sonarqube-public" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "jra-sonarqube-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "jra-sonarqube-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security groups (default-deny; no public inbound)
resource "aws_security_group" "app" {
  name        = "jra-sonarqube-app"
  description = "SonarQube app SG: port 9000 from itself only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SonarQube web port from within the app SG"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jra-sonarqube-app" }
}

resource "aws_security_group" "postgres" {
  name        = "jra-sonarqube-postgres"
  description = "PostgreSQL SG: port 5432 from the app SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the app SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jra-sonarqube-postgres" }
}

# S3 gateway endpoint (free; avoids NAT for S3 traffic)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = { Name = "jra-sonarqube-s3-ep" }
}

# ECS host role + instance profile (SSM core now; ECS policy added in slice 03)
resource "aws_iam_role" "ecs_host" {
  name = "jra-ecs-host"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = { Name = "jra-ecs-host" }
}

resource "aws_iam_role_policy_attachment" "ecs_host_ssm" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_host" {
  name = "jra-ecs-host"
  role = aws_iam_role.ecs_host.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "app_security_group_id" {
  description = "Application security group ID"
  value       = aws_security_group.app.id
}

output "ecs_host_instance_profile_name" {
  description = "ECS host instance profile name"
  value       = aws_iam_instance_profile.ecs_host.name
}
