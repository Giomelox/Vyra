# Vyra

Front-end com subpáginas dedicadas para as principais APIs públicas da NASA — dados atualizados automaticamente em background, sem intervenção manual.

## Visão geral

- **9 APIs da NASA** com ingestão agendada (frequência própria por API) + **Earth Imagery sob demanda** (usuário informa uma coordenada).
- Dados ficam em cache (S3 para imagens, DynamoDB para dados estruturados) — o front-end nunca chama a API da NASA diretamente no fluxo normal de navegação.
- Infraestrutura 100% como código (Terraform) e deploy automatizado (GitHub Actions).

## APIs incluídas

| API | Descrição | Frequência de ingestão | Baixa imagem? |
|---|---|---|---|
| APOD | Foto/vídeo astronômico do dia | 1x/dia | Sim (se `media_type=image`) |
| NeoWs | Asteroides próximos da Terra | 1x/dia | — |
| DONKI | Clima espacial (erupções solares, tempestades geomagnéticas) | 30 min | — |
| EPIC | Imagem quase em tempo real da Terra | 2h | Sim |
| EONET | Eventos naturais em andamento | 1h | — |
| Mars Rover Photos | Fotos mais recentes do rover Curiosity | 1x/dia | Sim |
| Exoplanet Archive | Exoplanetas confirmados mais recentes | 1x/dia | — |
| SSD/CNEOS | Aproximações de asteroides | 2h | — |
| TechPort | Projetos de tecnologia da NASA | 1x/dia | — |
| Earth Imagery | Imagem de satélite de uma coordenada | Sob demanda (não agendada) | Sim |

Não incluída: **InSight** (fora de escopo, decisão do projeto).

### Particularidades por API (importante)

Nem toda API usa `api.nasa.gov` + `api_key` da mesma forma:

- **APOD, DONKI, EPIC, Mars Rover Photos, TechPort**: endpoint padrão de `api.nasa.gov`, só precisam de `api_key`.
- **NeoWs**: exige `start_date`/`end_date` (sem default) — a Lambda usa o dia atual em UTC para os dois.
- **EONET**: domínio próprio (`eonet.gsfc.nasa.gov`), **não usa `api_key`**.
- **SSD/CNEOS**: domínio próprio da JPL (`ssd-api.jpl.nasa.gov`), **não usa `api_key`**.
- **Exoplanet Archive**: é um serviço TAP (query em ADQL, não um endpoint fixo), **não usa `api_key`**.

## Arquitetura

```
Route53 → CloudFront (+WAF) → ALB (+Cognito auth) → ECS Fargate (Next.js)
                                                          │
                              ┌───────────────────────────┼──────────────────────┐
                              ▼                            ▼                      ▼
                             S3                        DynamoDB              ElastiCache*
                       (imagens/binários)     (dados estruturados,        (cache quente,
                                                histórico, config)          versão robusta)
                              ▲
                              │
        EventBridge Scheduler (1 schedule por API)
                              │
                              ▼
                     Step Function (genérica)
                              │
                              ▼
              Lambda (1 por API, fora de VPC)
                              │
                    Secrets Manager (API key da NASA)
```

\* *ElastiCache, SNS, SQS, CloudWatch Alarms, Athena, CloudFront Functions/Lambda@Edge, Cognito, WAF e CloudFront fazem parte da arquitetura "robusta" planejada — a versão implementada em Terraform até agora é a versão SIMPLES (sem essas camadas), documentada abaixo.*

### O que foi de fato implementado (versão simples)

```
ALB (HTTP, sem HTTPS ainda) → ECS Fargate (Next.js)
                                    │
                        ┌───────────┼───────────┐
                        ▼           ▼           ▼
                       S3      DynamoDB    Secrets Manager
                                (3 tabelas)  (API key, lida
                                             pelo ECS p/ Earth
                                             Imagery e pelas
                                             Lambdas)
                        ▲
        EventBridge Scheduler (1 por API)
                        │
                        ▼
               Step Function genérica
                        │
                        ▼
        Lambda (1 por API, fora de VPC)
```

**Por que ALB já na versão simples?** Decisão explícita: sem ele, a task ECS ficaria exposta por IP público direto (instável, muda a cada deploy).

**Por que Step Function "genérica"?** Em vez de 9 branches (`Choice` state por API), ela recebe `{function_name, api_name}` no input e invoca a Lambda correspondente dinamicamente — um único `Task` state com `Retry`/`Catch` serve para as 9 ingestões.

**Por que as Lambdas de ingestão ficam fora da VPC?** Elas só fazem chamadas HTTP externas (para as APIs da NASA) — não precisam de rede privada, e isso evita pagar por um NAT Gateway sem necessidade.

**Por que 3 tabelas DynamoDB, não 1?**
- `api_data`: uma linha por API (estado atual), é o que o front-end lê.
- `history`: chave composta (`api_name` + `fetched_at`), permite comparação ao longo do tempo e também guarda as coordenadas já buscadas no Earth Imagery.
- `user_config`: separada de propósito — dado de usuário não deveria se misturar com dado de API.

**Por que sem RDS?** Configuração de usuário cabe perfeitamente no DynamoDB, sem o overhead de VPC/NAT Gateway/backup que o RDS exigiria.

## Estrutura do repositório

```
Vyra/
├── app/
│   ├── layout.tsx                  # layout raiz (navbar + estilos globais)
│   ├── page.tsx                    # home (grid de cards linkando cada API)
│   ├── globals.css
│   ├── [apiSlug]/page.tsx          # 1 rota dinâmica cobre as 9 subpáginas
│   ├── earth-imagery/page.tsx      # única página client-side (formulário)
│   └── api/earth-imagery/route.ts  # busca ao vivo + cache no S3
├── components/
│   └── Navbar.tsx
├── lib/
│   ├── aws.ts                      # clientes AWS compartilhados (S3, DynamoDB)
│   └── nasaApis.ts                 # config central: 1 fonte da verdade das 9 APIs
├── infra_dev_terraform/
│   ├── provider.tf                 # backend S3 + providers (aws, archive, tls)
│   ├── variables.tf                # inclui o map nasa_apis (schedule + endpoint por API)
│   ├── network.tf                  # VPC, subnets, ALB
│   ├── storage.tf                  # S3 + 3 tabelas DynamoDB
│   ├── security.tf                 # Secrets Manager (API key da NASA)
│   ├── iam.tf                      # roles: ECS (execution/task), Lambda (compartilhada)
│   ├── compute.tf                  # ECS cluster/task/service + 9 Lambdas (for_each)
│   ├── orchestration.tf            # Step Function + EventBridge Scheduler
│   ├── cicd.tf                     # OIDC provider + roles do GitHub Actions
│   ├── data.tf / main.tf / outputs.tf
│   ├── lambda/ingestion/*.py       # 1 handler Python por API
│   └── step_functions_definitions/
│       └── step_function_definition.json
├── .github/workflows/
│   ├── infra.yml                   # terraform plan (PR) + apply (main, aprovação manual)
│   └── app.yml                     # build/push Docker (ECR) + deploy (ECS, aprovação manual)
├── Dockerfile                      # multi-stage, output standalone do Next.js
└── .gitignore
```

## Rodando localmente

1. `npm install`
2. Copie `.env.local.example` para `.env.local` e preencha com os valores reais (saem dos `outputs.tf` do Terraform, **depois** de rodar `terraform apply` pelo menos uma vez):
   ```
   AWS_REGION=us-east-1
   API_DATA_TABLE=...
   HISTORY_TABLE=...
   USER_CONFIG_TABLE=...
   IMAGES_BUCKET=...
   NASA_API_KEY_SECRET_ARN=...
   ```
3. Configure credenciais AWS localmente (`aws configure` ou variáveis de ambiente) com permissão de leitura nas tabelas/bucket/secret — em produção, isso é resolvido automaticamente pela IAM role da task do ECS; local, não.
4. `npm run dev`

## Deploy / Infraestrutura

### Bootstrap (só na primeira vez, manual)

O CI/CD usa OIDC (GitHub assume uma role IAM na AWS, sem chaves salvas) — mas essa role **precisa existir antes** do GitHub Actions conseguir usá-la. Por isso o primeiro `terraform apply` (que inclui o `cicd.tf`) precisa ser feito **manualmente, com suas credenciais locais**:

```bash
cd infra_dev_terraform
terraform init
terraform apply  # com TF_VAR_nasa_api_key definida no ambiente
```

### Depois do bootstrap, configurar no GitHub

1. **Settings → Secrets and variables → Actions → Variables**:
   `AWS_INFRA_ROLE_ARN` e `AWS_APP_ROLE_ARN` (saem dos outputs do `cicd.tf`).
2. **Settings → Secrets**: `NASA_API_KEY`.
3. **Settings → Environments**: criar `infra-production` e `app-production`, cada uma com **required reviewers** (é isso que implementa a aprovação manual).

### A partir daí, o fluxo é automático

- **`infra.yml`**: PR que mexe em `infra_dev_terraform/**` roda `terraform plan` e comenta no PR; push na `main` roda `plan` de novo e pede aprovação manual antes do `apply`.
- **`app.yml`**: push na `main` (fora de `infra_dev_terraform/`) builda a imagem Docker, publica no ECR, e pede aprovação manual antes de forçar um novo deployment no ECS.

## Limitações conhecidas / próximos passos

- **Sem HTTPS ainda** — o listener do ALB é HTTP puro. HTTPS exige certificado ACM + domínio validado (Route53), que é peça da arquitetura robusta.
- **IAM da role de CI/CD (infra) é ampla, não least-privilege** — usa policies gerenciadas da AWS por serviço como ponto de partida prático. Apertar isso é trabalho de segurança contínuo.
- **Deploy do ECS via `:latest`** — `force-new-deployment` funciona, mas não é o ideal em termos de rastreabilidade (não fica óbvio qual commit está rodando). O mais robusto seria registrar uma nova revisão da task definition apontando pro digest exato da imagem.
- **Renderização de dados no front-end é JSON bruto** (`<pre>`) — cada API tem uma estrutura de resposta muito diferente; um viewer customizado por API é a evolução natural, não implementado ainda por decisão de escopo.
- **Download de imagem** (APOD/EPIC/Mars Rover) pega só 1 imagem por execução, não a lista inteira.
- **Arquitetura robusta** (Route53, CloudFront, WAF, Cognito, SNS, SQS, CloudWatch Alarms, Athena, ElastiCache, Lambda@Edge) está desenhada mas não implementada em Terraform — é evolução planejada, não MVP.
