# Bucket para imagens/binários (EPIC, Mars Rover Photos, Earth Imagery)
resource "aws_s3_bucket" "images" {
  bucket = "${var.project_name}-${var.environment}-images"

  tags = merge(var.tags, {
    Name = "${var.project_name}-images"
  })
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Tabela com os dados estruturados mais recentes de cada API
# (uma linha por api_name, sobrescrita a cada ingestão)
resource "aws_dynamodb_table" "api_data" {
  name         = "${var.project_name}-api-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "api_name"

  attribute {
    name = "api_name"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-api-data"
  })
}

# Histórico de ingestões, para comparação ao longo do tempo
# (ex: asteroides desse mes vs mes passado) e também usada para
# o histórico de coordenadas já buscadas no Earth Imagery.
resource "aws_dynamodb_table" "history" {
  name         = "${var.project_name}-history"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "api_name"
  range_key    = "fetched_at"

  attribute {
    name = "api_name"
    type = "S"
  }

  attribute {
    name = "fetched_at"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-history"
  })
}

# Configurações/preferências de usuário (sem RDS, ver arquitetura)
resource "aws_dynamodb_table" "user_config" {
  name         = "${var.project_name}-user-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-user-config"
  })
}