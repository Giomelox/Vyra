variable "project_name" {
  description = "Nome do projeto, usado como prefixo em recursos"
  type        = string
  default     = "vyra"
}

variable "environment" {
  description = "Ambiente (dev, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (uma por AZ, para o ECS Fargate)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "container_port" {
  description = "Porta exposta pelo container Next.js"
  type        = number
  default     = 3000
}

variable "ecs_task_cpu" {
  description = "CPU da task ECS (unidades Fargate)"
  type        = string
  default     = "256"
}

variable "ecs_task_memory" {
  description = "Memória da task ECS (MB)"
  type        = string
  default     = "512"
}

variable "ecs_desired_count" {
  description = "Quantidade de tasks do serviço ECS"
  type        = number
  default     = 1
}

# Lista de APIs da NASA com ingestão agendada.
# Earth Imagery fica de fora: é busca sob demanda, não ingestão agendada.
variable "nasa_apis" {
  description = "Configuração de cada API da NASA com ingestão via Lambda"
  type = map(object({
    schedule_expression = string # expressão do EventBridge Scheduler
    endpoint_path        = string # path do endpoint na api.nasa.gov
  }))
  default = {
    apod = {
      schedule_expression = "rate(1 day)"
      endpoint_path       = "/planetary/apod"
    }
    neows = {
      schedule_expression = "rate(1 day)"
      endpoint_path       = "/neo/rest/v1/feed"
    }
    donki = {
      schedule_expression = "rate(30 minutes)"
      endpoint_path       = "/DONKI/notifications"
    }
    epic = {
      schedule_expression = "rate(2 hours)"
      endpoint_path       = "/EPIC/api/natural"
    }
    eonet = {
      schedule_expression = "rate(1 hour)"
      endpoint_path       = "/EONET/v3/events"
    }
    mars_rover_photos = {
      schedule_expression = "rate(1 day)"
      endpoint_path       = "/mars-photos/api/v1/rovers/curiosity/latest_photos"
    }
    exoplanet_archive = {
      schedule_expression = "rate(1 day)"
      endpoint_path       = "/exoplanet"
    }
    ssd_cneos = {
      schedule_expression = "rate(2 hours)"
      endpoint_path       = "/cad"
    }
    techport = {
      schedule_expression = "rate(1 day)"
      endpoint_path       = "/techport"
    }
  }
}

variable "nasa_api_key_secret_name" {
  description = "Nome do secret no Secrets Manager que guarda a API key da NASA"
  type        = string
  default     = "vyra/nasa-api-key"
}

variable "nasa_api_key" {
  description = "API key da NASA (api.nasa.gov)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags padrão aplicadas a todos os recursos"
  type        = map(string)
  default = {
    Project   = "vyra"
    ManagedBy = "terraform"
  }
}
