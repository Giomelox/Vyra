# ---------------------------------------------------------------------------
# ECS - front-end (Next.js)
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-frontend"
  retention_in_days = 14
  tags              = var.tags
}

# Imagem do container: vem de um ECR gerenciado no main.tf. Referenciado
# aqui por nome, nao por valor cravado.
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:latest"
      essential = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [
        { name = "API_DATA_TABLE", value = aws_dynamodb_table.api_data.name },
        { name = "HISTORY_TABLE", value = aws_dynamodb_table.history.name },
        { name = "USER_CONFIG_TABLE", value = aws_dynamodb_table.user_config.name },
        { name = "IMAGES_BUCKET", value = aws_s3_bucket.images.bucket },
        { name = "AWS_REGION", value = var.aws_region },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = true # sem NAT Gateway - a task precisa de IP publico para puxar a imagem/pacotes
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "frontend"
    container_port   = var.container_port
  }

  # Garante que o listener já exista antes do ECS tentar se registrar no target group
  depends_on = [aws_lb_listener.http]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lambdas de ingestao - uma function por API (for_each sobre var.nasa_apis)
# ---------------------------------------------------------------------------
data "archive_file" "lambda_ingestion" {
  for_each = var.nasa_apis

  type        = "zip"
  source_file = "${path.module}/lambda/ingestion/${each.key}.py"
  output_path = "${path.module}/.build/${each.key}.zip"
}

resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  for_each = var.nasa_apis

  name              = "/aws/lambda/${var.project_name}-ingest-${each.key}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_lambda_function" "ingestion" {
  for_each = var.nasa_apis

  function_name    = "${var.project_name}-ingest-${each.key}"
  role             = aws_iam_role.lambda_ingestion.arn
  handler          = "${each.key}.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.lambda_ingestion[each.key].output_path
  source_code_hash = data.archive_file.lambda_ingestion[each.key].output_base64sha256

  environment {
    variables = {
      ENDPOINT_PATH           = each.value.endpoint_path
      IMAGES_BUCKET           = aws_s3_bucket.images.bucket
      API_DATA_TABLE          = aws_dynamodb_table.api_data.name
      HISTORY_TABLE           = aws_dynamodb_table.history.name
      NASA_API_KEY_SECRET_ARN = aws_secretsmanager_secret.nasa_api_key.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_ingestion]

  tags = var.tags
}
