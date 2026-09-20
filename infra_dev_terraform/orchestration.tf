# ---------------------------------------------------------------------------
# Step Function - orquestra a chamada de UMA Lambda de ingestao por execucao.
# É genérica de propósito: recebe {function_name, api_name} no input e
# invoca a Lambda certa - evita ter 9 branches/Choice states repetidos
# no JSON, um por API.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/${var.project_name}-ingestion"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-step-functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${var.project_name}-step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvocarLambdasDeIngestao"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        # Wildcard por prefixo: cobre as 9 lambdas atuais e futuras sem
        # precisar listar cada ARN (todas seguem o mesmo padrao de nome).
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-ingest-*"
      },
      {
        Sid    = "LogarExecucao"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "ingestion" {
  name     = "${var.project_name}-ingestion"
  role_arn = aws_iam_role.step_functions.arn
  definition = file("${path.module}/step_functions_definitions/step_function_definition.json")

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler - um schedule por API, cada um na sua frequencia
# (definida em var.nasa_apis), disparando a Step Function acima.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project_name}-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "IniciarExecucaoDaStepFunction"
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.ingestion.arn
    }]
  })
}

resource "aws_scheduler_schedule" "ingestion" {
  for_each = var.nasa_apis

  name       = "${var.project_name}-schedule-${each.key}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = each.value.schedule_expression

  target {
    arn      = aws_sfn_state_machine.ingestion.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      function_name = aws_lambda_function.ingestion[each.key].function_name
      api_name      = each.key
    })
  }
}
