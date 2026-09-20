# A API key em si NUNCA deve ir para o repositório ou para um .tfvars
# commitado - passe via variável de ambiente TF_VAR_nasa_api_key ou
# um .auto.tfvars ignorado no .gitignore.

resource "aws_secretsmanager_secret" "nasa_api_key" {
  name        = var.nasa_api_key_secret_name
  description = "API key da NASA (api.nasa.gov), usada pelas Lambdas de ingestao"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "nasa_api_key" {
  secret_id     = aws_secretsmanager_secret.nasa_api_key.id
  secret_string = var.nasa_api_key
}