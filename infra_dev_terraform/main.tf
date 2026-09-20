# Repositório ECR onde a imagem do front-end (Next.js) é publicada.
# O build/push da imagem fica fora do Terraform (CI/CD faz docker build +
# push); aqui só provisionamos o repositório em si.
resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}
