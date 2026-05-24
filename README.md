# Hospital Amazonas Pires — Cadastro de Pacientes

![CI/CD](https://github.com/SEU_USUARIO/hospital-amazonas-pires/actions/workflows/ci.yaml/badge.svg)
![Docker Hub](https://img.shields.io/docker/pulls/SEU_USUARIO/hospital-amazonas)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.29+-blue)
![License](https://img.shields.io/badge/license-MIT-green)

Sistema web de cadastro de pacientes hospitalares, usado como aplicação de referência para demonstrar um pipeline completo de CI/CD com segurança, deploy progressivo no Kubernetes via Kustomize e observabilidade full-stack.

---

## Índice

- [Visão geral](#visão-geral)
- [A aplicação](#a-aplicação)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Pré-requisitos](#pré-requisitos)
- [Rodando localmente](#rodando-localmente)
- [Docker](#docker)
- [Pipeline CI/CD](#pipeline-cicd)
- [Kubernetes e Kustomize](#kubernetes-e-kustomize)
- [Observabilidade](#observabilidade)
- [Secrets e variáveis](#secrets-e-variáveis)
- [Fluxo de trabalho com Git](#fluxo-de-trabalho-com-git)
- [Troubleshooting](#troubleshooting)

---

## Visão geral

```
Push  →  lint  →  build-test  →  security-scan  →  push (Docker Hub)
                                                        ↓
                                              deploy-dev (develop)
                                              deploy-staging (main)
                                                   └──→ [aprovação] → deploy-prod
                                                        ↓
                                          Prometheus · Loki · Tempo · OTel
                                                        ↓
                                                     Grafana
```

O projeto tem três objetivos:

1. **Aplicação funcional** — SPA hospitalar com CRUD de pacientes, filtros, paginação e persistência via localStorage.
2. **Referência de pipeline** — lint, build, testes automatizados, security scanning com Trivy, versionamento por SHA, deploy progressivo por ambiente e aprovação manual para produção.
3. **Observabilidade full-stack** — métricas (Prometheus + Grafana), logs centralizados (Loki + Promtail), rastreamento distribuído (Tempo + OpenTelemetry) e alertas via Alertmanager.

---

## A aplicação

SPA construída em HTML, CSS e JavaScript puro, sem framework. Servida por Nginx 1.27-alpine na porta `8080`.

### Funcionalidades

- Cadastro, edição e remoção de pacientes
- Campos: nome, CPF, data de nascimento, sexo, telefone, setor, status, leito, médico responsável e observações
- Status disponíveis: Ativo, Internado, Alta, Urgência
- Filtro por nome, CPF, ID, status e setor
- Paginação (8 registros por página)
- Views separadas: Pacientes, Internados, Urgência
- Dados de exemplo pré-carregados no primeiro acesso

### Endpoints

| Rota | Descrição |
|------|-----------|
| `GET /` | Retorna a aplicação (index.html) |
| `GET /health` | Health check — retorna `200 OK` |

O endpoint `/health` é usado pelo `HEALTHCHECK` do Dockerfile e pelas probes `readiness` e `liveness` do Kubernetes.

---

## Estrutura do repositório

```
hospital-amazonas-pires/
│
├── index.html                          # Aplicação (HTML + CSS + JS)
├── Dockerfile                          # Imagem nginx:1.27-alpine, porta 8080
├── nginx.conf                          # Gzip, cache, server_tokens off
├── .dockerignore
├── README.md
│
├── .github/
│   └── workflows/
│       └── ci.yaml                     # Pipeline CI/CD (7 jobs)
│
├── k8s/
│   ├── base/                           # Manifestos base — herdados pelos overlays
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml             # 2 réplicas, rolling update, probes
│   │   ├── service.yaml                # ClusterIP 80 → 8080
│   │   ├── ingress.yaml                # nginx ingress controller
│   │   ├── hpa.yaml                    # HPA: 2–6 réplicas, CPU 70%, memória 80%
│   │   ├── pdb.yaml                    # PodDisruptionBudget: minAvailable 1
│   │   └── network-policy.yaml         # Zero-trust: deny-all + allow seletivo
│   │
│   ├── overlays/
│   │   ├── dev/                        # 1 réplica, recursos menores, host dev.*
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   │       ├── deployment.yaml
│   │   │       ├── hpa.yaml
│   │   │       └── ingress.yaml
│   │   ├── staging/                    # Base intacta, host staging.*
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   │       ├── hpa.yaml
│   │   │       └── ingress.yaml
│   │   └── prod/                       # Base intacta, domínio real
│   │       ├── kustomization.yaml
│   │       └── patches/
│   │           └── ingress.yaml
│   │
│   └── observabilidade/
│       ├── namespace.yaml              # Namespace: monitoring
│       ├── prometheus.yaml             # Deployment + Service + RBAC
│       ├── prometheus-config.yaml      # Scrape configs + regras de alerta
│       ├── grafana.yaml                # Deployment + datasources + dashboard
│       ├── loki-promtail.yaml          # Loki + Promtail DaemonSet
│       ├── alertmanager.yaml           # Roteamento → Slack
│       ├── tempo-otel.yaml             # Tempo + OTel Collector
│       └── ingress.yaml                # Expõe Grafana externamente
│
├── docs/
│   └── runbook.md                      # Guia de resposta a alertas
│
└── .vscode/
    └── settings.json                   # Schema Kubernetes para YAML
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Para quê |
|------------|---------------|----------|
| Docker | 24+ | Build e execução local da imagem |
| kubectl | 1.29+ | Aplicar manifestos no cluster |
| Kustomize | 5+ | Gerenciar overlays por ambiente |
| Git | qualquer | Controle de versão |
| Cluster Kubernetes | 1.28+ | Deploy da aplicação |
| nginx ingress controller | — | Roteamento externo no cluster |
| Metrics Server | — | Necessário para o HPA funcionar |
| CNI com NetworkPolicy | — | Calico, Cilium ou Weave (flannel não suporta) |

### Instalar o Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Rodando localmente

Sem Docker, basta abrir o arquivo no navegador:

```bash
open index.html       # macOS
xdg-open index.html   # Linux
```

A aplicação funciona 100% no browser via localStorage — não há backend.

---

## Docker

### Build

```bash
docker build -t hospital-amazonas-pires:local .
```

### Rodar

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

### Parar e remover

```bash
docker rm -f hospital-amazonas-pires
```

---

## Pipeline CI/CD

Definido em `.github/workflows/ci.yaml`. Disparado em push nas branches `main` e `develop`, e em pull requests contra essas branches.

### Fluxo de jobs

```
lint → build-test → security-scan → push → deploy-dev     (develop)
                                         → deploy-staging  (main)
                                               └──→ [aprovação] → deploy-prod
```

| Job | Trigger | O que faz |
|-----|---------|-----------|
| `lint` | todos | Hadolint no Dockerfile + validação do nginx.conf |
| `build-test` | todos | Build da imagem, sobe container, testa `/` e `/health` |
| `security-scan` | todos | Trivy escaneia vulnerabilidades CRITICAL e HIGH; relatório SARIF enviado ao GitHub Security |
| `push` | push (não PR) | Publica imagem com tags `sha-<commit>`, `latest` ou `develop` |
| `deploy-dev` | push em `develop` | `kubectl apply -k k8s/overlays/dev` — automático |
| `deploy-staging` | push em `main` | `kubectl apply -k k8s/overlays/staging` — automático |
| `deploy-prod` | após staging | `kubectl apply -k k8s/overlays/prod` — **requer aprovação manual** |

### Versionamento de imagens

```
SEU_USUARIO/hospital-amazonas:sha-a3f9c12   ← commit exato (usado nos deploys)
SEU_USUARIO/hospital-amazonas:latest         ← último build da main
SEU_USUARIO/hospital-amazonas:develop        ← último build da develop
```

### Security scanning

O job `security-scan` usa [Trivy](https://github.com/aquasecurity/trivy) para escanear a imagem antes do push. CVEs com severidade `CRITICAL` ou `HIGH` que possuam correção disponível bloqueiam o pipeline. O relatório completo fica disponível na aba **Security → Code scanning** do repositório.

### Configurando a aprovação manual para prod

1. Acesse **Settings → Environments** no repositório
2. Crie os ambientes: `dev`, `staging` e `prod`
3. No ambiente `prod`, ative **Required reviewers** e adicione os aprovadores
4. Opcionalmente configure um **Wait timer** antes da janela de aprovação abrir

---

## Kubernetes e Kustomize

Os manifestos seguem a estrutura `base + overlays`. A base contém os recursos comuns; cada overlay aplica apenas o que difere por ambiente.

### Diferenças por ambiente

| Configuração | dev | staging | prod |
|---|---|---|---|
| Namespace | `dev` | `staging` | `prod` |
| Réplicas | 1 | 2 | 2 |
| HPA máximo | 3 | 4 | 6 |
| CPU request/limit | 25m / 50m | 50m / 100m | 50m / 100m |
| Memória request/limit | 32Mi / 64Mi | 64Mi / 128Mi | 64Mi / 128Mi |
| Host | `dev.hospital-amazonas-pires.local` | `staging.hospital-amazonas-pires.local` | `hospital-amazonas-pires.com` |

### Aplicar por ambiente

```bash
# Dev
kubectl apply -k k8s/overlays/dev

# Staging
kubectl apply -k k8s/overlays/staging

# Prod
kubectl apply -k k8s/overlays/prod
```

### Verificar o status do deploy

```bash
kubectl get pods -n prod
kubectl rollout status deployment/hospital-amazonas-pires -n prod
kubectl get hpa hospital-amazonas-pires -n prod -w
```

### Ver logs da aplicação

```bash
kubectl logs -l app=hospital-amazonas-pires -n prod --follow
```

### Rollback

```bash
kubectl rollout undo deployment/hospital-amazonas-pires -n prod
kubectl rollout status deployment/hospital-amazonas-pires -n prod
```

### Recursos de resiliência

| Recurso | Configuração | Efeito |
|---------|-------------|--------|
| HPA | CPU 70%, memória 80% | Escala automaticamente entre 2 e 6 réplicas |
| PDB | `minAvailable: 1` | Garante ao menos 1 réplica durante manutenção de node |
| NetworkPolicy | Zero-trust | Apenas ingress controller e namespace monitoring chegam aos pods |
| Rolling update | `maxUnavailable: 0` | Zero downtime durante deploys |

---

## Observabilidade

Toda a stack roda no namespace `monitoring`.

### Componentes

| Componente | Imagem | Porta | Responsabilidade |
|------------|--------|-------|-----------------|
| Prometheus | `prom/prometheus:v2.51.0` | 9090 | Coleta métricas, avalia alertas, retém 15 dias |
| Grafana | `grafana/grafana:10.4.2` | 3000 | Dashboards unificados |
| Loki | `grafana/loki:2.9.6` | 3100 | Armazena logs, retém 30 dias |
| Promtail | `grafana/promtail:2.9.6` | 9080 | DaemonSet que coleta logs de todos os pods |
| Alertmanager | `prom/alertmanager:v0.27.0` | 9093 | Roteia alertas por severidade → Slack |
| Tempo | `grafana/tempo:2.4.1` | 3200 | Armazena traces distribuídos, retém 48h |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.98.0` | 4317/4318 | Recebe e roteia telemetria OTLP |

### Aplicar a stack de observabilidade

```bash
kubectl apply -f k8s/observabilidade/
```

### Acessar o Grafana

```
URL:    http://grafana.hospital-amazonas-pires.local
Usuário: admin
Senha:   hospital-amazonas-pires-2025
```

> Em produção, substitua a senha por um `Secret` do Kubernetes.

O Grafana vem com datasource e dashboard provisionados automaticamente. O painel exibe: pods rodando, taxa de requisições por namespace, taxa de erros 5xx, latência p50/p95/p99, CPU, memória e restarts.

### Acessar Prometheus e Alertmanager

Ficam internos ao cluster por segurança. Use port-forward para acesso local:

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
```

### Regras de alerta

| Alerta | Condição | Severidade |
|--------|----------|------------|
| `PodDown` | Pod não pronto por mais de 1 minuto | critical |
| `PodCrashLooping` | Pod reiniciou mais de 1x em 5 minutos | warning |
| `HighErrorRate` | Taxa de erros 5xx acima de 5% | critical |
| `HighLatency` | Latência p95 acima de 2 segundos | warning |
| `HighCPU` | Uso de CPU acima de 80% do limite | warning |
| `HighMemory` | Memória acima de 100Mi | warning |

Alertas `critical` vão para `#hospital-amazonas-pires-critico` com menção `@channel`. Alertas `warning` vão para `#hospital-amazonas-pires-alertas`.

Para o guia de resposta a cada alerta, consulte o [runbook](docs/runbook.md).

### Configurar o Slack

Substitua `SEU_WEBHOOK_AQUI` em `k8s/observabilidade/alertmanager.yaml` pelo webhook real:

1. Acesse **api.slack.com/apps** → crie um app → **Incoming Webhooks**
2. Ative e adicione ao workspace
3. Copie a URL e cole no manifesto

### Enviar traces da aplicação

Aponte o endpoint OTLP para o OTel Collector:

```
gRPC: otel-collector.monitoring.svc.cluster.local:4317
HTTP: otel-collector.monitoring.svc.cluster.local:4318
```

### Observação para produção

Prometheus, Loki e Tempo usam `emptyDir` — os dados são perdidos se o pod reiniciar. Em produção, substitua por `PersistentVolumeClaim`:

```yaml
volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: prometheus-pvc
```

---

## Secrets e variáveis

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Descrição |
|--------|-----------|
| `DOCKERHUB_USERNAME` | Usuário do Docker Hub |
| `DOCKERHUB_TOKEN` | Access Token — hub.docker.com → Security |
| `KUBECONFIG_DEV` | Kubeconfig do cluster dev em base64 |
| `KUBECONFIG_STAGING` | Kubeconfig do cluster staging em base64 |
| `KUBECONFIG_PROD` | Kubeconfig do cluster prod em base64 |

### Gerar o base64 do kubeconfig

```bash
cat ~/.kube/config | base64 -w 0
```

---

## Fluxo de trabalho com Git

```
main      →  staging + prod (com aprovação manual)
develop   →  dev (automático)
```

### Nova feature

```bash
# 1. Criar branch a partir de develop
git checkout develop && git pull origin develop
git checkout -b feature/nome-da-feature

# 2. Desenvolver e commitar
git add . && git commit -m "feat: descrição da mudança"

# 3. Abrir PR para develop
# → pipeline roda lint + build + security-scan (sem deploy)
# → merge dispara deploy automático em dev

# 4. Quando dev estiver validado, abrir PR de develop → main
# → merge dispara deploy em staging
# → aprovação manual libera prod
```

---

## Troubleshooting

### Container não sobe localmente

```bash
docker logs hospital-amazonas-pires
lsof -i :8080
```

### Pod em CrashLoopBackOff

```bash
kubectl logs <pod> -n <namespace> --previous
kubectl describe pod <pod> -n <namespace>
```

### Pipeline falha no security-scan

O Trivy encontrou uma vulnerabilidade `CRITICAL` ou `HIGH` com correção disponível. Consulte o relatório em **Security → Code scanning** para identificar o CVE e atualize a imagem base ou o pacote afetado.

### HPA não está escalando

```bash
kubectl describe hpa hospital-amazonas-pires -n <namespace>
kubectl top pods -n <namespace>
```

Se `kubectl top` retornar erro, o Metrics Server pode estar down — verifique em `kube-system`.

### NetworkPolicy bloqueando tráfego

```bash
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <nome> -n <namespace>
```

Verifique se o CNI instalado no cluster suporta NetworkPolicy (Calico, Cilium ou Weave). O flannel padrão não aplica as políticas.

### Deploy travado em `Pending`

```bash
kubectl get nodes
kubectl describe deployment hospital-amazonas-pires -n <namespace>
```

### Imagem não encontrada (`ImagePullBackOff`)

```bash
kubectl describe pod <pod> -n <namespace>
# Procure por "Events" no final da saída
```

### Grafana não carrega dados

```bash
kubectl get pods -n monitoring
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Acesse http://localhost:9090/targets e verifique o status dos scrape jobs
```

### Logs não aparecem no Loki

```bash
kubectl get pods -n monitoring -l app=promtail
kubectl logs -l app=promtail -n monitoring --tail=50
```

### Alertas não chegam no Slack

```bash
kubectl get pods -n monitoring -l app=alertmanager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Acesse http://localhost:9093 e verifique os alertas ativos
```

### Arquivos YAML com erro de schema no VS Code

Confirme que a extensão **YAML** da Red Hat (`redhat.vscode-yaml`) está instalada e que o `.vscode/settings.json` está presente. Use `Ctrl+Shift+P` → **Developer: Reload Window** após salvar.

Para recursos que geram ambiguidade no schema global, adicione a diretiva inline na primeira linha do arquivo:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.32.1-standalone-strict/deployment-apps-v1.json
```

| Recurso | Schema |
|---------|--------|
| Deployment | `deployment-apps-v1.json` |
| Service | `service-v1.json` |
| Ingress | `ingress-networking-v1.json` |
| HPA | `horizontalpodautoscaler-autoscaling-v2.json` |
| ConfigMap | `configmap-v1.json` |
| NetworkPolicy | `networkpolicy-networking-v1.json` |
