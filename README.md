# n8n Lab — Kubernetes Local com Observabilidade

Lab local para simular o ambiente n8n de produção (namespace `hub`) com pipeline completo de logs via Fluentd → Elasticsearch → Kibana.

**Stack:** n8n 2.2.4 · PostgreSQL 15 · Redis 7 · Fluentd 1.19 · Elasticsearch 8.13 · Kibana 8.13 · kind (Kubernetes in Docker)

---

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│  namespace: hub                                  │
│                                                  │
│  n8n-master ←──── Redis (fila de jobs)           │
│      │                    ↑                      │
│  PostgreSQL          n8n-worker                  │
└──────────────────────────────────────────────────┘
          │ stdout (logs)
          ↓
┌─────────────────────────────────────────────────┐
│  namespace: logging                              │
│                                                  │
│  Fluentd (DaemonSet)                             │
│    └── lê /var/log/containers/*.log (CRI)        │
│    └── enriquece com kubernetes_metadata         │
│    └── parseia formato n8n (regexp)              │
│    └── envia para Elasticsearch                  │
│                                                  │
│  Elasticsearch ← índices legacy-YYYY.MM.DD       │
│  Kibana        ← Data View: legacy-*             │
└──────────────────────────────────────────────────┘
```

**Portas expostas no host:**

| Serviço       | Host          | Como                  |
|---------------|---------------|-----------------------|
| n8n           | localhost:5678 | NodePort 30678       |
| Elasticsearch | localhost:9200 | NodePort 30920       |
| Kibana        | localhost:5601 | ModePort 30601       |

---

## Pré-requisitos

```bash
kind version
kubectl version --client
docker ps | grep kind
```

Confirme que o cluster está ativo:

```bash
kubectl cluster-info --context kind-lab
```

Se não existir, crie:

```bash
kind create cluster --config kind-config.yml
```

---

## Deploy rápido

```bash
./deploy.sh
```

O script sobe toda a stack em ordem e aguarda cada componente ficar pronto. Ao final exibe os endpoints disponíveis.

---

## Deploy passo a passo

### Passo 1 — Namespaces

```bash
kubectl apply -f namespace.yaml
```

Cria os namespaces `hub` (n8n) e `logging` (ELK).

---

### Passo 2 — Secret

```bash
kubectl apply -f secret.yaml
```

> Credenciais de lab. Nunca use em produção.

---

### Passo 3 — Redis

```bash
kubectl apply -f redis.yaml
kubectl wait --for=condition=ready pod -l app=redis -n hub --timeout=60s
```

---

### Passo 4 — PostgreSQL

```bash
kubectl apply -f postgres.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n hub --timeout=120s
```

---

### Passo 5 — ConfigMap do n8n

```bash
kubectl apply -f configmap.yaml
```

---

### Passo 6 — n8n Master

```bash
kubectl apply -f n8n-master.yaml
kubectl wait --for=condition=ready pod -l app=n8n-master -n hub --timeout=180s
```

Pronto quando os logs exibirem:
```
Editor is now accessible via: http://localhost:5678/
```

---

### Passo 7 — n8n Worker

```bash
kubectl apply -f n8n-worker.yaml
kubectl wait --for=condition=ready pod -l app=n8n-worker -n hub --timeout=120s
```

---

### Passo 8 — Elasticsearch

```bash
kubectl apply -f elasticsearch.yaml
kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=180s
```

---

### Passo 9 — Fluentd

```bash
kubectl apply -f fluentd-configmap.yaml
kubectl apply -f fluentd-daemonset.yaml
kubectl rollout status daemonset/fluentd -n logging --timeout=120s
```

O Fluentd roda como DaemonSet — um pod por node. Lê os logs dos containers via CRI, filtra o namespace `hub`, parseia o formato n8n e envia ao Elasticsearch com prefixo `legacy-`.

---

### Passo 10 — Kibana

```bash
kubectl apply -f kibana.yaml
kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=180s
```

---

## Acessando os serviços

### n8n — http://localhost:5678

Porta mapeada via NodePort 30678 no `kind-config.yml`. Acesso direto.

No primeiro acesso crie o usuário admin. O n8n opera em modo **queue**: o master distribui, o worker executa.

### Elasticsearch — http://localhost:9200

Porta mapeada via NodePort 30920 no `kind-config.yml`. Acesso direto.

```bash
curl http://localhost:9200/_cat/indices?v
```

### Kibana — http://localhost:5601

Requer port-forward enquanto o cluster atual não for recriado:

```bash
kubectl port-forward -n logging svc/kibana 5601:5601
```

Para rodar em background:

```bash
kubectl port-forward -n logging svc/kibana 5601:5601 &
```

#### Configurar Data View no Kibana

1. Acesse `http://localhost:5601`
2. Menu → **Management** → **Stack Management** → **Data Views**
3. Clique em **Create data view**
4. Index pattern: `legacy-*`
5. Timestamp field: `@timestamp`
6. Salve e acesse em **Discover**

---

## Validando o pipeline de logs

### Verificar índices criados

```bash
curl -s "http://localhost:9200/_cat/indices?v"
```

Esperado: índices `legacy-YYYY.MM.DD` com documentos.

### Volume de logs por pod

```bash
curl -s "http://localhost:9200/legacy-*/_search?pretty&size=0" \
  -H "Content-Type: application/json" \
  -d '{
    "aggs": {
      "por_pod": {
        "terms": {"field": "kubernetes.pod_name.keyword"}
      }
    }
  }'
```

### Buscar mensagens específicas

```bash
curl -s "http://localhost:9200/legacy-*/_search?pretty&size=5" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {"match": {"application.message": "TEST_"}},
    "_source": ["application.message", "application.level", "kubernetes.pod_name", "@timestamp"]
  }'
```

---

## Workflows de teste

Três workflows para validar a captura de logs:

### Workflow 1 — Log de sucesso

Nodes: `[Manual Trigger]` → `[Code]`

```javascript
console.log("TEST_FLOW_START: workflow de teste executando");
return items;
```

### Workflow 2 — Log de erro

Nodes: `[Manual Trigger]` → `[Code]`

```javascript
throw new Error("TEST_ERROR: erro simulado para validar captura no ES");
```

### Workflow 3 — Volume contínuo

Nodes: `[Schedule Trigger: a cada 1 min]` → `[Code]`

```javascript
console.log(`TEST_LOOP: execução ${new Date().toISOString()}`);
return items;
```

Após executar os workflows, valide no Elasticsearch que as mensagens `TEST_*` chegaram com os campos `application.message`, `application.level` e `kubernetes.pod_name` populados.

---

## Esquema de campos no Elasticsearch

Os logs do namespace `hub` são indexados no padrão `legacy-*`, compatível com o schema de produção:

| Campo | Descrição |
|-------|-----------|
| `@timestamp` | Timestamp do log |
| `kubernetes.namespace_name` | Namespace (`hub`) |
| `kubernetes.pod_name` | Nome do pod |
| `kubernetes.labels.app` | Label app do pod |
| `application.message` | Mensagem do log (parseada do formato n8n) |
| `application.level` | Nível do log (info, warn, error) |
| `application.timestamp` | Timestamp original do n8n |

---

## Comandos úteis

### Ver todos os pods

```bash
kubectl get pods -n hub
kubectl get pods -n logging
```

### Logs em tempo real

```bash
kubectl logs -f -l app=n8n-master -n hub
kubectl logs -f -l app=n8n-worker -n hub
kubectl logs -f -l app=fluentd -n logging
```

### Reiniciar após mudança de configmap

```bash
kubectl apply -f configmap.yaml
kubectl rollout restart deployment/n8n-master-deployment -n hub
kubectl rollout restart deployment/n8n-worker-deployment -n hub
```

### Acessar PostgreSQL

```bash
kubectl exec -it -n hub deployment/postgres-deployment -- psql -U n8n -d n8n
```

### Acessar Redis

```bash
kubectl exec -it -n hub deployment/redis-deployment -- redis-cli
```

### Acessar Elasticsearch (dentro do cluster)

```bash
kubectl exec -it -n logging elasticsearch-0 -- curl -s http://localhost:9200/_cat/indices?v
```

---

## Destruir o ambiente

### Remover todos os recursos (mantém o cluster kind)

```bash
./destroy.sh
```

### Remover o cluster inteiro

```bash
kind delete cluster --name lab
```

---

## Diferenças em relação à produção

| Aspecto | Produção | Lab |
|---------|----------|-----|
| Banco de dados | Azure PostgreSQL via pgbouncer (6432) | PostgreSQL 15 local (5432) |
| Redis | Azure Cache for Redis com TLS (6380) | Redis 7 local sem TLS (6379) |
| Protocolo | HTTPS com domínio real | HTTP + localhost |
| Worker replicas | 4 | 1 |
| Memory worker limit | 6Gi | 1Gi |
| Node selector | `purpose=applications-od` (AKS OD nodes) | Removido |
| WEBHOOK_URL | `https://n8n.production.domain.com/` | `http://localhost:5678/` |
| Kibana | Não integrado localmente | Deployado no namespace `logging` |
| Namespace filter (Fluentd) | `production` | `hub` |

---

## Estrutura dos arquivos

```
n8n-lab/
├── kind-config.yml          # Configuração do cluster kind (portas: 5678, 9200, 5601)
├── deploy.sh                # Sobe toda a stack em ordem
├── destroy.sh               # Remove todos os recursos
├── namespace.yaml           # Namespaces: hub e logging
├── secret.yaml              # Credenciais (DB, encryption key)
├── configmap.yaml           # Variáveis de ambiente do n8n
├── redis.yaml               # Redis deployment + service
├── postgres.yaml            # PostgreSQL deployment + PVC + service
├── n8n-master.yaml          # n8n master deployment + NodePort 30678
├── n8n-worker.yaml          # n8n worker deployment
├── elasticsearch.yaml       # Elasticsearch StatefulSet + services + NodePort 30920
├── fluentd-configmap.yaml   # Configuração do Fluentd (parse, filter, output)
├── fluentd-daemonset.yaml   # Fluentd DaemonSet + RBAC
└── kibana.yaml              # Kibana deployment + NodePort 30601
```
