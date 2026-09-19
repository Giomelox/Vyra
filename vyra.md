# Portal NASA APIs — Arquiteturas

## Escopo do projeto
- Front-end moderno (não "dashboard") com subpágina dedicada para cada API pública da NASA
- APIs incluídas: APOD, NeoWs, DONKI, EPIC, EONET, Mars Rover Photos, Earth Imagery, Exoplanet Archive, SSD/CNEOS, TechPort/TechTransfer (exceto InSight)
- Earth Imagery: usuário informa coordenada e recebe a imagem correspondente (busca sob demanda, não pré-cacheada)
- Frequência de atualização do cache varia por API, cada uma no seu ritmo natural
- Earth Imagery também salva histórico das coordenadas já buscadas

---

## Arquitetura Simples

```
Front-end (Next.js dockerizado, ECS)
        │  (via API interna — não acesso direto e livre ao S3/DynamoDB)
        ▼
S3 (imagens/binários: EPIC, Mars Rover Photos, Earth Imagery)
DynamoDB (dados estruturados das demais APIs)
        ▲
EventBridge (schedule) → Lambda (requisições agendadas às APIs da NASA)
```

**Observações:**
- EventBridge → Lambda → S3/DynamoDB é um pipeline de ingestão independente, roda sozinho, não passa pelo front-end.
- O front-end não deve ter IAM amplo direto pro S3/DynamoDB — precisa de uma camada de API (API routes do Next.js, ou API Gateway + Lambda) com permissão restrita.
- S3 fica reservado para imagens/binários; dados JSON estruturados vão para DynamoDB.

---

## Arquitetura Robusta (validada)

```
Route53
   │
   ▼
CloudFront (com WAF anexado, otimização de imagem via CloudFront Functions/Lambda@Edge)
   │
   ▼
ALB (com autenticação Cognito configurada no listener)
   │
   ▼
ECS (Next.js dockerizado)
   │  (via API interna)
   ├────────────────────┬──────────────────┐
   ▼                    ▼                  ▼
S3                  DynamoDB          ElastiCache (Redis)
(imagens)     (dados estruturados,    (cache quente na frente
              histórico, config)       do DynamoDB)
   ▲
   │
EventBridge (schedule por API) → Lambda (uma por API, fora de VPC) → SQS (fila para
   │                                                                  processamento pesado futuro)
   ├─ Secrets Manager (API key da NASA)
   ├─ SNS (alertas: tempestade solar, asteroide próximo, etc)
   └─ CloudWatch Alarms (falha de alguma Lambda de ingestão)

Athena → consultas ad-hoc sobre o histórico acumulado no S3/DynamoDB
```

**Serviços complementares:**

| Serviço | Papel na arquitetura |
|---|---|
| Secrets Manager | Guarda a API key da NASA, usada pelas Lambdas de ingestão |
| SNS | Dispara alertas em eventos relevantes (DONKI, NeoWs) |
| SQS | Fila entre a Lambda de ingestão e um futuro processamento pesado (ex: transformação de imagens) |
| CloudWatch Alarms | Alerta se alguma Lambda de ingestão falhar ou parar de rodar |
| Athena | Consulta o histórico acumulado no S3/DynamoDB sem infra extra de banco |
| CloudFront Functions / Lambda@Edge | Redimensiona/otimiza imagens (EPIC, Mars Rover) na borda |
| ElastiCache (Redis) | Cache quente na frente do DynamoDB para páginas de alto tráfego |

**Correções aplicadas em relação à proposta inicial:**
1. **ALB obrigatório** entre CloudFront e ECS — CloudFront não fala direto com ECS.
2. **Cognito não é um hop separado** — é uma regra de autenticação configurada no listener do ALB, antes de rotear pro target group.
3. **Ordem correta**: Route53 → CloudFront (+WAF) → ALB (+Cognito) → ECS.
4. **RDS descartado** — configuração de usuário fica no DynamoDB, evitando overhead de VPC/NAT Gateway/backup que o RDS exigiria. RDS só se justificaria com necessidade real de queries relacionais complexas.
5. **Lambdas de ingestão ficam fora de VPC** — chamada para API externa (NASA) não precisa de rede privada; colocar em VPC só adicionaria custo (NAT Gateway) e complexidade sem necessidade.

---

## Frequência de atualização por API

| API | Frequência sugerida | Motivo |
|---|---|---|
| DONKI | 15–30 min | eventos podem surgir a qualquer hora |
| NeoWs | 1x/dia | dado diário por natureza |
| EPIC | 1–2h | imagem muda a cada poucas horas |
| EONET | 30–60 min | eventos em andamento |
| Mars Rover Photos | 1x/dia | rovers não enviam foto nova toda hora |
| APOD | 1x/dia | é literalmente "do dia" |
| Exoplanet Archive | 1x/dia (ou semanal) | catálogo, muda pouco |
| SSD/CNEOS | 1–2h | aproximações de asteroides |
| TechPort/TechTransfer | 1x/dia | catálogo estático na prática |

---

## Decisões já fechadas
- Uma Lambda por API (não genérica) — isolamento de falhas
- RDS descartado em favor de DynamoDB para configurações de usuário
