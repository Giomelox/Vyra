output "alb_dns_name" {
  description = "DNS público do ALB (URL de acesso ao front-end por enquanto)"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "URL do repositório ECR para push da imagem do front-end"
  value       = aws_ecr_repository.frontend.repository_url
}

output "images_bucket_name" {
  description = "Nome do bucket S3 de imagens"
  value       = aws_s3_bucket.images.bucket
}

output "api_data_table_name" {
  description = "Nome da tabela DynamoDB com os dados mais recentes de cada API"
  value       = aws_dynamodb_table.api_data.name
}

output "history_table_name" {
  description = "Nome da tabela DynamoDB de histórico"
  value       = aws_dynamodb_table.history.name
}

output "user_config_table_name" {
  description = "Nome da tabela DynamoDB de configuração de usuário"
  value       = aws_dynamodb_table.user_config.name
}

output "step_function_arn" {
  description = "ARN da Step Function de ingestão"
  value       = aws_sfn_state_machine.ingestion.arn
}

output "nasa_api_key_secret_arn" {
  description = "ARN do secret com a API key da NASA"
  value       = aws_secretsmanager_secret.nasa_api_key.arn
}
