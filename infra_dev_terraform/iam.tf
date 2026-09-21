# ---------------------------------------------------------------------------
# ECS - Execution Role
# Usada pelo próprio ECS para: puxar a imagem do container e escrever logs.
# Não é a role da aplicação em si - é a role "de infraestrutura" da task.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# ECS - Task Role
# Usada pela APLICAÇÃO (Next.js) em tempo de execução, para ler o cache
# (S3/DynamoDB) e, no caso do Earth Imagery, gravar o resultado sob demanda.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LerCacheDeApis"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = [
          aws_dynamodb_table.api_data.arn,
          "${aws_dynamodb_table.api_data.arn}/index/*",
        ]
      },
      {
        Sid    = "LerEGravarHistorico"
        Effect = "Allow"
        # Leitura para consulta de historico e Query, escrita para o
        # fluxo sob demanda do Earth Imagery (salva a coordenada buscada).
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:PutItem"]
        Resource = [
          aws_dynamodb_table.history.arn,
          "${aws_dynamodb_table.history.arn}/index/*",
        ]
      },
      {
        Sid      = "GerenciarConfigDeUsuario"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.user_config.arn
      },
      {
        Sid    = "LerEGravarImagens"
        Effect = "Allow"
        # HeadObject usa a mesma permissao de s3:GetObject - e o que o
        # backend do Next.js usa pra checar se uma coordenada do Earth
        # Imagery ja foi buscada antes, sem precisar de acao extra.
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Sid    = "LerApiKeyDaNasaParaEarthImagery"
        Effect = "Allow"
        # Earth Imagery e sob demanda (chamado direto pelo backend do
        # front-end, nao por uma Lambda de ingestao) - por isso a task
        # role tambem precisa ler o secret, diferente das outras APIs.
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.nasa_api_key.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambdas de ingestão - role COMPARTILHADA entre as 9 funções.
#
# Decisão: uma role só, não uma por Lambda. O isolamento que importa (uma
# API falhando não derruba as outras) já vem de serem 9 *funções* Lambda
# separadas, com logs e métricas próprios. Como todas fazem exatamente a
# mesma coisa (ler o secret, chamar a API, escrever no mesmo bucket/tabelas),
# 9 roles idênticas só multiplicariam recursos sem ganho real de segurança.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_ingestion" {
  name = "${var.project_name}-lambda-ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_ingestion_logs" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ingestion" {
  name = "${var.project_name}-lambda-ingestion-policy"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LerApiKeyDaNasa"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.nasa_api_key.arn
      },
      {
        Sid      = "GravarImagensNoS3"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Sid      = "GravarDadosEstruturados"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [
          aws_dynamodb_table.api_data.arn,
          aws_dynamodb_table.history.arn,
        ]
      }
    ]
  })
}