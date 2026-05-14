# Runbook — Hospital Amazonas Pires

Guia operacional para resposta a alertas em produção.  
Cada seção corresponde a um alerta definido em `k8s/observabilidade/prometheus-config.yaml`.

> **Convenção de severidade**
> - 🔴 `critical` — impacto direto ao usuário, resposta imediata
> - 🟡 `warning` — degradação, investigar na próxima hora

---

## Índice

- [PodDown](#poddown) 🔴
- [PodCrashLooping](#podcrashloopping) 🔴
- [HighErrorRate](#higherrorrate) 🔴
- [HighLatency](#highlatency) 🟡
- [HighCPU](#highcpu) 🟡
- [HighMemory](#highmemory) 🟡

---

## PodDown

**Severidade:** 🔴 critical  
**Dispara quando:** `kube_pod_status_ready == 0` por mais de 1 minuto  
**Impacto:** réplicas abaixo do mínimo — tráfego concentrado nos pods restantes ou serviço indisponível

### 1. Confirmar o problema

```bash
# Ver estado dos pods no namespace afetado
kubectl get pods -n <namespace> -o wide

# Detalhes do pod — checar Events no final da saída
kubectl describe pod <pod> -n <namespace>

# Logs do container atual e do anterior (se houve restart)
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
```

### 2. Causas mais comuns e ações

| Sinal no `describe` | Causa | Ação |
|---|---|---|
| `OOMKilled` | Limite de memória atingido | Aumentar `memory limit` em `deployment.yaml` e redeployar |
| `CrashLoopBackOff` | Aplicação falhando na inicialização | Ver [PodCrashLooping](#podcrashloopping) |
| `ImagePullBackOff` | Imagem não encontrada no Docker Hub | Verificar tag da imagem e credenciais do registry |
| `Pending` sem node | Cluster sem recursos disponíveis | `kubectl describe node` — checar pressão de CPU/memória |
| Readiness probe falhando | `/health` não responde | Checar se Nginx subiu corretamente nos logs |

### 3. Forçar rollback se o problema veio de um deploy

```bash
kubectl rollout history deployment/hospital-amazonas-pires -n <namespace>
kubectl rollout undo deployment/hospital-amazonas-pires -n <namespace>
kubectl rollout status deployment/hospital-amazonas-pires -n <namespace>
```

### 4. Escalar se não resolver em 15 min

Acionar responsável pelo cluster. Verificar se o problema afeta outros deployments no mesmo namespace.

---

## PodCrashLooping

**Severidade:** 🔴 critical  
**Dispara quando:** taxa de restarts > 0 por 2 minutos consecutivos  
**Impacto:** pod reiniciando em loop — indisponível durante os backoffs (10s, 20s, 40s, 80s…)

### 1. Confirmar o problema

```bash
# Ver contagem de restarts
kubectl get pods -n <namespace>

# Quantas vezes reiniciou e quando foi o último restart
kubectl describe pod <pod> -n <namespace> | grep -A5 "Last State"

# Logs do container que morreu
kubectl logs <pod> -n <namespace> --previous
```

### 2. Causas mais comuns e ações

| Sinal nos logs | Causa | Ação |
|---|---|---|
| `exit code 1` sem mensagem | Erro de configuração do Nginx | Validar `nginx.conf` localmente: `nginx -t` |
| `exit code 137` | OOMKill — ver [HighMemory](#highmemory) | Aumentar `memory limit` |
| `exit code 139` | Segfault — problema na imagem | Rebuild da imagem, verificar base `nginx:1.27-alpine` |
| Nenhum log | Container morre antes de logar | Checar `readinessProbe` e `livenessProbe` em `deployment.yaml` |

### 3. Parar o loop para investigar sem pressão

```bash
# Reduzir para 0 réplicas temporariamente (apenas em dev/staging)
kubectl scale deployment/hospital-amazonas-pires --replicas=0 -n <namespace>

# Subir um pod de debug com a mesma imagem
kubectl run debug --image=<imagem> -it --restart=Never -n <namespace> -- sh
```

### 4. Após correção

```bash
kubectl scale deployment/hospital-amazonas-pires --replicas=2 -n <namespace>
kubectl rollout status deployment/hospital-amazonas-pires -n <namespace>
```

---

## HighErrorRate

**Severidade:** 🔴 critical  
**Dispara quando:** erros 5xx > 5% das requisições por 2 minutos  
**Impacto:** usuários recebendo erro — funcionalidade da aplicação comprometida

### 1. Confirmar o problema

```bash
# Ver se os pods estão healthy
kubectl get pods -n <namespace>

# Logs do Nginx em tempo real
kubectl logs -l app=hospital-amazonas-pires -n <namespace> --follow

# Checar o ingress controller
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --follow
```

### 2. Consultar no Grafana

Abrir o painel **HospitalOS — Overview** e verificar:
- Painel *Taxa de erros 5xx (%)* — confirmar o namespace e o horário de início
- Painel *Taxa de requisições (req/s)* — ver se houve pico de tráfego antes dos erros

### 3. Causas mais comuns e ações

| Situação | Causa | Ação |
|---|---|---|
| Pods em CrashLoop | Aplicação falhando | Ver [PodCrashLooping](#podcrashloopping) |
| Pods healthy, erros no ingress | Configuração do ingress | `kubectl describe ingress -n <namespace>` |
| Erro após deploy recente | Regressão no código | `kubectl rollout undo deployment/hospital-amazonas-pires -n <namespace>` |
| Pods healthy, sem deploy recente | Pressão de recursos | Checar [HighCPU](#highcpu) e [HighMemory](#highmemory) |

### 4. Rollback rápido

```bash
kubectl rollout undo deployment/hospital-amazonas-pires -n <namespace>
kubectl rollout status deployment/hospital-amazonas-pires -n <namespace> --timeout=60s
```

---

## HighLatency

**Severidade:** 🟡 warning  
**Dispara quando:** latência p95 > 2 segundos por 5 minutos  
**Impacto:** experiência degradada — usuários aguardando mais que o esperado

### 1. Confirmar o problema

```bash
# Ver uso de recursos dos pods
kubectl top pods -n <namespace>

# Ver uso de recursos dos nodes
kubectl top nodes
```

### 2. Consultar no Grafana

Verificar no painel **HospitalOS — Overview**:
- *Latência p50 / p95 / p99* — confirmar qual percentil está alto
- *CPU usage* e *Memória* — ver se há correlação com pressão de recursos
- *Taxa de requisições* — checar se há pico de tráfego simultâneo

### 3. Causas mais comuns e ações

| Situação | Causa | Ação |
|---|---|---|
| CPU alta nos pods | Requisições acima da capacidade | HPA deve estar escalando — aguardar novos pods subirem |
| CPU normal, latência alta | Gargalo no ingress controller | Checar métricas do ingress-nginx |
| Latência só em p99 | Requisições pesadas isoladas | Investigar padrão de acesso nos logs do Nginx |
| Latência em todos os percentis | Problema de rede ou node | `kubectl describe node` — checar condições do node |

### 4. Escalar manualmente se o HPA não reagir rápido o suficiente

```bash
kubectl scale deployment/hospital-amazonas-pires --replicas=4 -n <namespace>
```

---

## HighCPU

**Severidade:** 🟡 warning  
**Dispara quando:** uso de CPU > 80% do limit (> 80m de 100m) por 5 minutos  
**Impacto:** throttling iminente — pode causar latência elevada e erros

### 1. Confirmar o problema

```bash
# Uso atual de CPU por pod
kubectl top pods -n <namespace>

# Ver o limit configurado
kubectl describe deployment hospital-amazonas-pires -n <namespace> | grep -A4 "Limits"
```

### 2. Causas mais comuns e ações

| Situação | Causa | Ação |
|---|---|---|
| Pico de tráfego | Carga legítima | HPA deve escalar — monitorar por 5 min |
| CPU alta sem tráfego | Loop infinito ou processo runaway | `kubectl exec -it <pod> -n <namespace> -- top` |
| CPU alta após deploy | Regressão de performance | Rollback e investigar |

### 3. Se o HPA não estiver escalando

```bash
# Ver estado atual do HPA
kubectl describe hpa hospital-amazonas-pires -n <namespace>

# Verificar se o Metrics Server está respondendo
kubectl top pods -n <namespace>
```

Se `kubectl top` retornar erro, o Metrics Server pode estar down — verificar no namespace `kube-system`.

### 4. Ajuste permanente de resources (abrir PR)

Se o uso de CPU for consistentemente alto e legítimo, aumentar os valores em `deployment.yaml`:

```yaml
resources:
  requests:
    cpu: "100m"   # era 50m
  limits:
    cpu: "200m"   # era 100m
```

---

## HighMemory

**Severidade:** 🟡 warning  
**Dispara quando:** memória > 100Mi (limit é 128Mi) por 5 minutos  
**Impacto:** risco de OOMKill — se ultrapassar 128Mi o container é reiniciado pelo kernel

### 1. Confirmar o problema

```bash
# Uso atual de memória por pod
kubectl top pods -n <namespace>

# Ver o limit configurado
kubectl describe deployment hospital-amazonas-pires -n <namespace> | grep -A4 "Limits"
```

### 2. Contexto importante para este projeto

A aplicação é uma SPA estática servida pelo Nginx — consumo de memória normalmente é baixo e estável (~10-20Mi). Uso acima de 100Mi é incomum e quase sempre indica um dos cenários abaixo.

| Situação | Causa | Ação |
|---|---|---|
| Crescimento lento e constante | Memory leak no Nginx worker | Reiniciar o pod: `kubectl rollout restart deployment/hospital-amazonas-pires -n <namespace>` |
| Pico súbito | Muitas conexões simultâneas | Checar tráfego — pode ser DDoS ou crawler |
| Após deploy recente | Regressão na configuração do Nginx | Rollback e comparar `nginx.conf` |

### 3. Reinício controlado sem downtime

```bash
# Rolling restart — substitui os pods um a um respeitando o PDB
kubectl rollout restart deployment/hospital-amazonas-pires -n <namespace>
kubectl rollout status deployment/hospital-amazonas-pires -n <namespace>
```

### 4. Ajuste permanente de resources (abrir PR)

Se o uso for legítimo e recorrente, aumentar em `deployment.yaml`:

```yaml
resources:
  requests:
    memory: "128Mi"  # era 64Mi
  limits:
    memory: "256Mi"  # era 128Mi
```

---

## Referências rápidas

```bash
# Ver todos os alertas ativos no Alertmanager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Acessar: http://localhost:9093

# Ver métricas brutas no Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Acessar: http://localhost:9090

# Abrir o Grafana localmente
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Acessar: http://localhost:3000 (admin / hospital-amazonas-pires-2025)

# Ver logs de qualquer pod em tempo real
kubectl logs -l app=hospital-amazonas-pires -n <namespace> --follow --tail=100
```
