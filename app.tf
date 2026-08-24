# ---------------------------------------------------------------------------
# Slices 04 + 05 - PostgreSQL + SonarQube containers
# Two containers in one task, one service; SonarQube reaches PostgreSQL via
# localhost (shared network namespace in awsvpc mode).
# ---------------------------------------------------------------------------

# Role ECS uses to create/attach the PGDATA EBS volume at task launch
resource "aws_iam_role" "ecs_volume" {
  name = "jra-ecs-volume"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_volume_policy" {
  role       = aws_iam_role.ecs_volume.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "jra-sonarqube"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "2048"
  memory                   = "6144"

  task_role_arn      = aws_iam_role.sonarqube_task.arn
  execution_role_arn = aws_iam_role.sonarqube_task.arn

  volume {
    name                = "pgdata"
    configure_at_launch = true
  }

  # SonarQube data: host bind mount. The AWS provider supports only ONE
  # managed-EBS volume_configuration per aws_ecs_service, which pgdata uses.
  # (A bind mount on the host root EBS survives task replacement; the managed
  # EBS is delete-on-termination and is recreated on any container stop.)
  volume {
    name      = "sonarqube_data"
    host_path = "/var/lib/sonarqube-data"
  }

  container_definitions = jsonencode([
    {
      name      = "postgres"
      image     = "postgres:17"
      essential = true

      environment = [
        { name = "POSTGRES_USER", value = "sonar" },
        { name = "POSTGRES_DB", value = "sonar" },
      ]

      secrets = [
        { name = "POSTGRES_PASSWORD", valueFrom = aws_secretsmanager_secret.postgres_app.arn },
      ]

      mountPoints = [
        {
          sourceVolume  = "pgdata"
          containerPath = "/var/lib/postgresql/data"
          readOnly      = false
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "pg_isready -U sonar"]
        interval    = 10
        timeout     = 5
        retries     = 10
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/jra-sonarqube"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "postgres"
        }
      }
    },
    {
      name      = "sonarqube"
      image     = var.sonarqube_image
      essential = true

      environment = [
        { name = "SONAR_JDBC_URL", value = "jdbc:postgresql://localhost:5432/sonar" },
        { name = "SONAR_JDBC_USERNAME", value = "sonar" },
        { name = "SONAR_ES_BOOTSTRAP_CHECKS_DISABLE", value = "true" },
      ]

      secrets = [
        { name = "SONAR_JDBC_PASSWORD", valueFrom = aws_secretsmanager_secret.postgres_app.arn },
      ]

      portMappings = [
        { containerPort = 9000, protocol = "tcp" }
      ]

      mountPoints = [
        {
          sourceVolume  = "sonarqube_data"
          containerPath = "/opt/sonarqube/data"
          readOnly      = false
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://localhost:9000/api/system/status 2>/dev/null | grep -q UP || wget -qO- http://localhost:9000/api/system/status 2>/dev/null | grep -q UP"]
        interval    = 30
        timeout     = 10
        retries     = 10
        startPeriod = 300
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/jra-sonarqube"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "sonarqube"
        }
      }

      cpu               = 1536
      memoryReservation = 4096
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "jra-sonarqube"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

  # Singleton: stop the old task before starting the new one (the task uses
  # the full 2 vCPU / 6 GiB of the host, so old+new can't overlap).
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  network_configuration {
    subnets         = [aws_subnet.public.id]
    security_groups = [aws_security_group.app.id]
  }

  volume_configuration {
    name = "pgdata"
    managed_ebs_volume {
      role_arn    = aws_iam_role.ecs_volume.arn
      size_in_gb  = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
}
