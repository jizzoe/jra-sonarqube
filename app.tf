# ---------------------------------------------------------------------------
# Slice 04 - PostgreSQL container (slice 05 adds the SonarQube container)
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
  cpu                      = "512"
  memory                   = "1024"

  task_role_arn      = aws_iam_role.sonarqube_task.arn
  execution_role_arn = aws_iam_role.sonarqube_task.arn

  volume {
    name                = "pgdata"
    configure_at_launch = true
  }

  container_definitions = jsonencode([
    {
      name      = "postgres"
      image     = "postgres:17"
      essential = true

      environment = [
        { name = "POSTGRES_USER", value = "postgres" },
        { name = "POSTGRES_DB", value = "sonar" },
      ]

      secrets = [
        { name = "POSTGRES_PASSWORD", valueFrom = aws_secretsmanager_secret.postgres_superuser.arn },
        { name = "SONAR_APP_PASSWORD", valueFrom = aws_secretsmanager_secret.postgres_app.arn },
      ]

      mountPoints = [
        {
          sourceVolume  = "pgdata"
          containerPath = "/var/lib/postgresql/data"
          readOnly      = false
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "pg_isready -U postgres"]
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
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "jra-sonarqube"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

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
