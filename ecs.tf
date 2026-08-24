# ---------------------------------------------------------------------------
# Slice 03 - ECS cluster (EC2) & host bootstrap
# ---------------------------------------------------------------------------

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }
}

# ECS host role: add the ECS container-service policy (SSM core was attached in slice 02)
resource "aws_iam_role_policy_attachment" "ecs_host_ecs" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# ECS host role: allow the rexray EBS volume plugin to create/attach PGDATA volume
resource "aws_iam_role_policy" "ecs_host_ebs" {
  name = "ecs-host-ebs-volume"
  role = aws_iam_role.ecs_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags",
        ]
        Resource = "*"
      },
    ]
  })
}

# Host security group: no inbound, all outbound (Option 2: SSM + image pulls egress)
resource "aws_security_group" "host" {
  name        = "jra-sonarqube-host"
  description = "ECS host SG: no inbound, all outbound"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jra-sonarqube-host" }
}

locals {
  ecs_host_user_data = <<-EOT
    #!/bin/bash
    # SonarQube / Elasticsearch Linux prerequisites + ECS cluster registration

    # 1. Kernel sysctls (Elasticsearch requirement)
    cat > /etc/sysctl.d/99-sonarqube.conf <<'SYSCTL'
    vm.max_map_count=262144
    fs.file-max=131072
    SYSCTL
    sysctl --system >/dev/null

    # 2. File-descriptor and process limits
    cat > /etc/security/limits.d/99-sonarqube.conf <<'LIMITS'
    * soft nofile 131072
    * hard nofile 131072
    * soft nproc 8192
    * hard nproc 8192
    LIMITS

    # 3. Register with the ECS cluster (the agent reads this at its normal
    #    start, which happens after cloud-init/user-data by design).
    echo ECS_CLUSTER=jra-sonarqube >> /etc/ecs/ecs.config

    # 4. SonarQube data bind-mount directory (host_path volume). chmod 777 so
    #    the SonarQube container user can write regardless of its UID.
    mkdir -p /var/lib/sonarqube-data
    chmod 777 /var/lib/sonarqube-data

    # 5. PostgreSQL data bind-mount directory (UID 999 = postgres).
    mkdir -p /var/lib/postgresql-data
    chown 999:999 /var/lib/postgresql-data
  EOT
}

resource "aws_launch_template" "ecs_host" {
  name_prefix   = "jra-sonarqube-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.host_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_host.name
  }

  vpc_security_group_ids = [aws_security_group.host.id]

  user_data = base64encode(local.ecs_host_user_data)

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "jra-sonarqube-host" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "jra-sonarqube-host" }
  }
}

resource "aws_autoscaling_group" "ecs_host" {
  name             = "jra-sonarqube-asg"
  min_size         = 0
  max_size         = 1
  desired_capacity = 0

  vpc_zone_identifier = [aws_subnet.public.id]

  launch_template {
    id      = aws_launch_template.ecs_host.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "jra-sonarqube-host"
    propagate_at_launch = true
  }

  # ECS managed scaling owns desired_capacity (0 when idle, 1 when a task
  # needs capacity); Terraform only sets the baseline min/max.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_ecs_cluster" "main" {
  name = "jra-sonarqube"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "jra-sonarqube-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_host.arn

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}
