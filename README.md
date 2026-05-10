# Hospital Amazonas Pires — Cadastro de Pacientes

Sistema web de cadastro de pacientes hospitalares, usado como aplicação de referência para demonstrar um pipeline completo de CI/CD com deploy no Kubernetes e observabilidade full-stack.

---

## Índice

- [Visão geral](#visão-geral)
- [A aplicação](#a-aplicação)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Rodando localmente](#rodando-localmente)
- [Docker](#docker)
- [Pipeline CI/CD](#pipeline-cicd)
- [Kubernetes](#kubernetes)
- [Ambientes](#ambientes)
- [Observabilidade](#observabilidade)
- [Secrets e variáveis](#secrets-e-variáveis)
- [Fluxo de trabalho com Git](#fluxo-de-trabalho-com-git)
- [Troubleshooting](#troubleshooting)

---

## Visão geral

```
Código  →  Git Push  →  CI (lint, build, test)  →  Docker Hub  →  Kubernetes
                                                                   dev / staging / prod
                                                                        ↓
                                                              Prometheus · Loki · Tempo
                                                                        ↓
                                                                     Grafana
```

O projeto tem três objetivos:

1. **Aplicação funcional** — um mini sistema hospitalar com CRUD completo de pacientes, filtros, paginação e persistência via localStorage.
2. **Referência de pipeline** — demonstra boas práticas de CI/CD: validação de Dockerfile, testes automatizados, versionamento de imagem por commit SHA, deploy progressivo por ambiente e aprovação manual para produção.
3. **Observabilidade full-stack** — métricas com Prometheus + Grafana, logs centralizados com Loki + Promtail, rastreamento distribuído com Tempo + OpenTelemetry e alertas via Alertmanager.

---

## A aplicação

**Hospital Amazonas Pires** é uma SPA (Single Page Application) construída em HTML, CSS e JavaScript puro, sem dependências de framework. É servida por um Nginx 1.27-alpine rodando na porta `8080`.

### Funcionalidades

- Cadastro, edição e remoção de pacientes
- Campos: nome, CPF, data de nascimento, sexo, telefone, setor, status, leito, médico responsável e observações
- Status disponíveis: Ativo, Internado, Alta, Urgência
- Filtro por nome, CPF, ID, status e setor
- Paginação (8 registros por página)
- Views separadas: Pacientes, Internados, Urgência
- Dados de exemplo pré-carregados no primeiro acesso

### Endpoints expostos pelo Nginx

| Rota | Descrição |
|------|-----------|
| `GET /` | Retorna a aplicação (index.html) |
| `GET /health` | Health check — retorna `200 OK` |

O endpoint `/health` é usado tanto pelo `HEALTHCHECK` do Dockerfile quanto pelas probes `readiness` e `liveness` do Kubernetes.

---

## Estrutura do repositório

```
HOSPITAL/
│
├── index.html                        # Aplicação completa (HTML + CSS + JS)
├── Dockerfile                        # Imagem baseada em nginx:1.27-alpine
├── nginx.conf                        # Configuração do servidor web (porta 8080)
├── .dockerignore                     # Exclui arquivos desnecessários do build
├── README.md                         # Esta documentação
│
├── k8s/
│   ├── deployment.yaml               # 2 réplicas, rolling update, probes
│   ├── service.yaml                  # ClusterIP — expõe porta 80 → 8080
│   ├── ingress.yaml                  # Entrada externa via nginx ingress controller
│   │
│   └── observabilidade/
│       ├── namespace.yaml            # Namespace: monitoring
│       ├── prometheus-config.yaml    # ConfigMap com scrape configs e regras de alerta
│       ├── prometheus.yaml           # Deployment + Service + RBAC do Prometheus
│       ├── grafana.yaml              # Deployment + Service + dashboards provisionados
│       ├── loki-promtail.yaml        # Loki (armazenamento) + Promtail (DaemonSet coletor)
│       ├── alertmanager.yaml         # Roteamento de alertas → Slack
│       ├── tempo-otel.yaml           # Tempo (traces) + OpenTelemetry Collector
│       └── ingress.yaml              # Expõe Grafana externamente
│
├── .vscode/
│   └── settings.json                 # Schema Kubernetes para arquivos YAML
│
└── .github/
    └── workflows/
        └── ci.yml                    # Pipeline CI/CD completo (6 jobs)
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Para quê |
|------------|---------------|----------|
| Docker | 24+ | Build e execução local da imagem |
| kubectl | 1.29+ | Aplicar manifestos no cluster |
| Git | qualquer | Controle de versão |
| Conta Docker Hub | — | Registry de imagens |
| Cluster Kubernetes | 1.28+ | Deploy da aplicação |
| nginx ingress controller | — | Roteamento externo no cluster |
| Extensão YAML (Red Hat) | — | Validação de YAML no VS Code |

---

## Rodando localmente

Sem Docker, basta abrir o arquivo direto no navegador:

```bash
open index.html
# ou
xdg-open index.html   # Linux
```

Como não há backend real, a aplicação funciona 100% no browser via localStorage.

---

## Docker

### Build da imagem

```bash
docker build -t hospital-amazonas-pires:local .
```

### Rodar o container

```bash
docker run -d \
  --name hospital-amazonas-pires \
  -p 8080:8080 \
  hospital-amazonas-pires:local
```

Acesse em: [http://localhost:8080](http://localhost:8080)

### Verificar o health check

```bash
curl http://localhost:8080/health
# Resposta esperada: ok
```

### Parar e remover o container

```bash
docker rm -f hospital-amazonas-pires
```

### Gerar tag com commit SHA (padrão do pipeline)

```bash
SHA=$(git rev-parse --short HEAD)
docker build -t seu-usuario/hospital-amazonas-pires:sha-${SHA} .
docker push seu-usuario/hospital-amazonas-pires:sha-${SHA}
```

---

## Pipeline CI/CD

O pipeline é definido em `.github/workflows/ci.yml` e é disparado em:

- **Push** nas branches `main` ou `develop`
- **Pull Request** aberto contra `main` ou `develop`

### Jobs e ordem de execução

```
lint  →  build-test  →  push  →  deploy-dev     (branch develop)
                              →  deploy-staging  (branch main)
                                    └──→  [aprovação manual]
                                              └──→  deploy-prod
```

| Job | Trigger | O que faz |
|-----|---------|-----------|
| `lint` | todos | Valida Dockerfile (Hadolint) e nginx.conf |
| `build-test` | todos | Build da imagem, sobe container, testa `/` e `/health` |
| `push` | push (não PR) | Publica imagem com tags `sha-<commit>` e `latest` ou `develop` |
| `deploy-dev` | push em `develop` | `kubectl apply` no namespace `dev` — automático |
| `deploy-staging` | push em `main` | `kubectl apply` no namespace `staging` — automático |
| `deploy-prod` | após staging aprovado | `kubectl apply` no namespace `prod` — **requer aprovação manual** |

### Versionamento de imagens

Cada imagem publicada recebe duas tags:

```
seu-usuario/hospital-amazonas-pires:sha-a3f9c12   ← identifica o commit exato
seu-usuario/hospital-amazonas-pires:latest         ← aponta sempre para o último build da main
seu-usuario/hospital-amazonas-pires:develop        ← aponta sempre para o último build da develop
```

A tag `sha-` é a usada nos deploys — garante rastreabilidade total entre o pod rodando no cluster e o commit que gerou a imagem.

### Configurando a aprovação manual para prod

1. Acesse **Settings → Environments** no repositório
2. Crie os ambientes: `dev`, `staging` e `prod`
3. No ambiente `prod`, ative **Required reviewers** e adicione os aprovadores
4. Opcionalmente configure um **Wait timer** (ex: 5 minutos) antes da janela de aprovação abrir

Quando um push chega na `main`, o pipeline pausa automaticamente antes do job `deploy-prod` e envia uma notificação para os revisores. O deploy só prossegue após a aprovação explícita.

---

## Kubernetes

### Aplicar a aplicação

```bash
# Dev
kubectl apply -f k8s/ -n dev

# Staging
kubectl apply -f k8s/ -n staging

# Prod
kubectl apply -f k8s/ -n prod
```

### Verificar o status do deploy

```bash
kubectl get pods -n prod
kubectl rollout status deployment/hospital-amazonas-pires -n prod
```

### Ver logs da aplicação

```bash
kubectl logs -l app=hospital-amazonas-pires -n prod --tail=100 -f
```

### Forçar rollback para a versão anterior

```bash
kubectl rollout undo deployment/hospital-amazonas-pires -n prod
kubectl rollout status deployment/hospital-amazonas-pires -n prod
```

### Verificar qual imagem está rodando

```bash
kubectl get deployment hospital-amazonas-pires -n prod \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Detalhes do Deployment

O `deployment.yaml` está configurado com:

- **2 réplicas** — alta disponibilidade
- **RollingUpdate** com `maxUnavailable: 0` — zero downtime durante deploys
- **readinessProbe** em `/health` — o K8s só manda tráfego quando o pod estiver pronto
- **livenessProbe** em `/health` — reinicia automaticamente pods não responsivos
- **podAntiAffinity** — distribui os pods em nodes físicos diferentes
- **Limites de recursos** — `50m/64Mi` de request e `100m/128Mi` de limit

> **Atenção:** Antes de aplicar no cluster, substitua `SEU_USUARIO` pela sua conta do Docker Hub no arquivo `k8s/deployment.yaml`.

---

## Ambientes

| Ambiente | Branch | Deploy | Namespace | URL |
|----------|--------|--------|-----------|-----|
| dev | `develop` | automático | `dev` | http://dev.hospital-amazonas-pires.local |
| staging | `main` | automático | `staging` | http://staging.hospital-amazonas-pires.local |
| prod | `main` | **aprovação manual** | `prod` | http://hospital-amazonas-pires.com |

Cada ambiente tem seu próprio namespace Kubernetes e seu próprio kubeconfig armazenado como secret no GitHub Actions.

---

## Observabilidade

A stack de observabilidade roda no namespace `monitoring` e cobre as três dimensões: métricas, logs e traces.

### Visão geral da stack

```
pods (dev/staging/prod)
  │
  ├── métricas  →  Prometheus  →  Grafana
  ├── logs      →  Promtail    →  Loki    →  Grafana
  ├── traces    →  OTel Collector  →  Tempo  →  Grafana
  └── alertas   →  Alertmanager  →  Slack
```

### Componentes

| Componente | Imagem | Porta | Responsabilidade |
|------------|--------|-------|-----------------|
| Prometheus | `prom/prometheus:v2.51.0` | 9090 | Coleta e armazena métricas via scrape |
| Grafana | `grafana/grafana:10.4.2` | 3000 | Dashboards unificados de métricas, logs e traces |
| Loki | `grafana/loki:2.9.6` | 3100 | Armazena e indexa logs por 30 dias |
| Promtail | `grafana/promtail:2.9.6` | 9080 | DaemonSet que coleta logs de todos os pods |
| Alertmanager | `prom/alertmanager:v0.27.0` | 9093 | Roteia alertas por severidade para o Slack |
| Tempo | `grafana/tempo:2.4.1` | 3200 | Armazena traces distribuídos por 48h |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.98.0` | 4317/4318 | Recebe e roteia traces via OTLP |

### Aplicar a stack de observabilidade

```bash
kubectl apply -f k8s/observabilidade/
```

### Acessar o Grafana

```
URL:   http://grafana.hospital-amazonas-pires.local
Usuário: admin
Senha:   hospital-amazonas-pires-2025
```

> **Importante:** troque a senha antes de ir para produção. Em produção, use um `Secret` do Kubernetes em vez de deixar a senha em texto no manifesto.

O Grafana já vem com datasources e dashboard do Hospital Amazonas Pires provisionados automaticamente. O dashboard exibe: pods rodando, taxa de requisições por namespace, taxa de erros 5xx, latência p50/p95/p99, uso de CPU e memória, e restarts de pods.

### Acessar Prometheus e Alertmanager

Prometheus e Alertmanager ficam internos ao cluster por segurança. Para acessar localmente use port-forward:

```bash
# Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Alertmanager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
```

### Regras de alerta configuradas

| Alerta | Condição | Severidade |
|--------|----------|------------|
| `PodDown` | Pod não pronto por mais de 1 minuto | critical |
| `PodCrashLooping` | Pod reiniciou mais de 1x em 5 minutos | warning |
| `HighErrorRate` | Taxa de erros 5xx acima de 5% | critical |
| `HighLatency` | Latência p95 acima de 2 segundos | warning |
| `HighCPU` | Uso de CPU acima de 80% do limite | warning |
| `HighMemory` | Memória acima de 100Mi | warning |

Alertas com severidade `critical` são enviados para `#hospital-amazonas-pires-critico` com menção `@channel`. Alertas `warning` vão para `#hospital-amazonas-pires-alertas`.

### Configurar o Slack

Substitua `SEU_WEBHOOK_AQUI` no arquivo `k8s/observabilidade/alertmanager.yaml` pelo webhook real:

1. Acesse **api.slack.com/apps** → crie um app → **Incoming Webhooks**
2. Ative e adicione ao workspace
3. Copie a URL gerada e cole no manifesto

### Enviar traces da aplicação

Para instrumentar a aplicação e enviar traces ao OTel Collector, aponte o endpoint OTLP para:

```
grpc: otel-collector.monitoring.svc.cluster.local:4317
http: otel-collector.monitoring.svc.cluster.local:4318
```

### Observações para produção

Os volumes de Prometheus, Loki e Tempo estão configurados com `emptyDir`, o que significa que os dados são perdidos se o pod reiniciar. Em produção, substitua por `PersistentVolumeClaim`:

```yaml
volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: prometheus-pvc   # criar o PVC antes de aplicar
```

---

## Secrets e variáveis

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Descrição |
|--------|-----------|
| `DOCKERHUB_USERNAME` | Usuário do Docker Hub |
| `DOCKERHUB_TOKEN` | Access Token gerado em hub.docker.com → Security |
| `KUBECONFIG_DEV` | Conteúdo do kubeconfig do cluster dev, em base64 |
| `KUBECONFIG_STAGING` | Conteúdo do kubeconfig do cluster staging, em base64 |
| `KUBECONFIG_PROD` | Conteúdo do kubeconfig do cluster prod, em base64 |

### Como gerar o base64 do kubeconfig

```bash
cat ~/.kube/config | base64 -w 0
# Cole o resultado como valor do secret correspondente
```

---

## Fluxo de trabalho com Git

O repositório segue o modelo de duas branches principais:

```
main      →  staging + prod (com aprovação)
develop   →  dev (automático)
```

### Fluxo recomendado para uma nova feature

```bash
# 1. Criar branch a partir de develop
git checkout develop
git pull origin develop
git checkout -b feature/nome-da-feature

# 2. Desenvolver e commitar
git add .
git commit -m "feat: descrição da mudança"

# 3. Abrir PR para develop
# → pipeline roda lint + build + test (sem deploy)
# → após aprovação e merge, deploy automático vai para dev

# 4. Quando dev estiver validado, abrir PR de develop → main
# → merge dispara deploy automático para staging
# → após validação em staging, aprovação manual libera prod
```

---

## Troubleshooting

### Container não sobe localmente

```bash
docker logs hospital-amazonas-pires
lsof -i :8080
```

### Pod em CrashLoopBackOff no cluster

```bash
kubectl logs <nome-do-pod> -n <namespace> --previous
kubectl describe pod <nome-do-pod> -n <namespace>
```

### Pipeline falha no job de lint

O Hadolint pode reclamar de instruções no Dockerfile. Consulte as [regras do Hadolint](https://github.com/hadolint/hadolint#rules) para entender o erro e corrigir.

### Deploy travado em `Pending`

```bash
kubectl get nodes
kubectl describe deployment hospital-amazonas-pires -n <namespace>
```

### Imagem não encontrada no cluster (`ImagePullBackOff`)

Verifique se o nome da imagem em `deployment.yaml` está correto, se a imagem foi publicada no registry e se o cluster tem acesso à internet.

```bash
kubectl describe pod <nome-do-pod> -n <namespace>
# Procure por "Events" no final da saída
```

### Grafana não carrega dados

```bash
# Verificar se o Prometheus está rodando
kubectl get pods -n monitoring

# Verificar se o Prometheus consegue fazer scrape
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Acesse http://localhost:9090/targets e verifique o status
```

### Logs não aparecem no Grafana/Loki

```bash
# Verificar se o Promtail está rodando em todos os nodes
kubectl get pods -n monitoring -l app=promtail

# Ver logs do Promtail para diagnosticar erros de coleta
kubectl logs -l app=promtail -n monitoring --tail=50
```

### Alertas não chegam no Slack

```bash
# Verificar se o Alertmanager está rodando
kubectl get pods -n monitoring -l app=alertmanager

# Acessar a UI do Alertmanager para ver alertas ativos
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Acesse http://localhost:9093
```

### Arquivos YAML com erros de schema no VS Code

Verifique se o `.vscode/settings.json` contém:

```json
{
  "yaml.schemas": {
    "kubernetes": ["k8s/**/*.yaml"]
  },
  "yaml.schemaStore.enable": false,
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml"
  },
  "files.associations": {
    "k8s/**/*.yaml": "yaml"
  }
}
```

E confirme que a extensão **YAML** da Red Hat (`redhat.vscode-yaml`) está instalada. Use `Ctrl+Shift+P` → **Developer: Reload Window** após salvar o arquivo.

### Erro "Matches multiple schemas when only one must validate"

O mapeamento `"kubernetes"` em `yaml.schemas` usa um schema combinado (`all.json`) que valida todos os tipos K8s em modo `oneOf` estrito — em alguns manifestos isso gera ambiguidade e o validador acusa o erro acima. A solução é apontar o arquivo para o schema específico do recurso usando uma diretiva inline na primeira linha:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.32.1-standalone-strict/service-v1.json
```

Troque `service-v1.json` pelo schema correspondente ao recurso:

| Recurso | Schema |
|---------|--------|
| Deployment | `deployment-apps-v1.json` |
| Service | `service-v1.json` |
| Ingress | `ingress-networking-v1.json` |
| ConfigMap | `configmap-v1.json` |
| Namespace | `namespace-v1.json` |

A diretiva inline tem prioridade sobre o mapeamento global do `settings.json` e remove a ambiguidade do `oneOf`.