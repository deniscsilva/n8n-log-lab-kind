#!/bin/bash
set -e

CONTEXT="kind-lab"
NAMESPACE="hub"
NAMESPACE_LOGGING="logging"
LAB_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Usando context: $CONTEXT"
kubectl config use-context $CONTEXT

echo ""
echo "==> [1/7] Namespace"
kubectl apply -f "$LAB_DIR/namespace.yaml"

echo ""
echo "==> [2/7] Secret"
kubectl apply -f "$LAB_DIR/secret.yaml"

echo ""
echo "==> [3/7] Redis"
kubectl apply -f "$LAB_DIR/redis.yaml"
kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=60s

echo ""
echo "==> [4/7] PostgreSQL"
kubectl apply -f "$LAB_DIR/postgres.yaml"
kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=120s

echo ""
echo "==> [5/7] ConfigMap"
kubectl apply -f "$LAB_DIR/configmap.yaml"

echo ""
echo "==> [6/7] n8n Master"
kubectl apply -f "$LAB_DIR/n8n-master.yaml"
kubectl wait --for=condition=ready pod -l app=n8n-master -n $NAMESPACE --timeout=180s

echo ""
echo "==> [7/7] n8n Worker"
kubectl apply -f "$LAB_DIR/n8n-worker.yaml"
kubectl wait --for=condition=ready pod -l app=n8n-worker -n $NAMESPACE --timeout=120s

echo ""
echo "==> [8/9] Elasticsearch"
kubectl apply -f "$LAB_DIR/elasticsearch.yaml"
kubectl wait --for=condition=ready pod -l app=elasticsearch -n $NAMESPACE_LOGGING --timeout=180s

echo ""
echo "==> [9/10] Fluentd (ConfigMap + DaemonSet)"
kubectl apply -f "$LAB_DIR/fluentd-configmap.yaml"
kubectl apply -f "$LAB_DIR/fluentd-daemonset.yaml"
kubectl rollout status daemonset/fluentd -n $NAMESPACE_LOGGING --timeout=120s

echo ""
echo "==> [10/10] Kibana"
kubectl apply -f "$LAB_DIR/kibana.yaml"
kubectl wait --for=condition=ready pod -l app=kibana -n $NAMESPACE_LOGGING --timeout=180s

echo ""
echo "==> Deploy concluido!"
echo ""
echo "--- namespace: $NAMESPACE ---"
kubectl get all -n $NAMESPACE
echo ""
echo "--- namespace: $NAMESPACE_LOGGING ---"
kubectl get all -n $NAMESPACE_LOGGING
echo ""
echo "==> Endpoints:"
echo "    n8n:           http://localhost:5678"
echo "    Elasticsearch: http://localhost:9200"
echo "    Kibana:        http://localhost:5601  (requer port-forward: kubectl port-forward -n logging svc/kibana 5601:5601)"
echo "                   Porta 5601 sera mapeada diretamente apos recriar o cluster com o kind-config.yml atualizado"
