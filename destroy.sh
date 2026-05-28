#!/bin/bash
set -e

CONTEXT="kind-lab"
NAMESPACE="hub"
NAMESPACE_LOGGING="logging"

echo "==> Usando context: $CONTEXT"
kubectl config use-context $CONTEXT

echo ""
echo "==> Removendo RBAC do Fluentd (cluster-scoped)..."
kubectl delete clusterrolebinding fluentd --ignore-not-found
kubectl delete clusterrole fluentd --ignore-not-found

echo ""
echo "==> Removendo namespace '$NAMESPACE_LOGGING' (Elasticsearch + Fluentd + Kibana)..."
kubectl delete namespace $NAMESPACE_LOGGING --ignore-not-found

echo ""
echo "==> Removendo namespace '$NAMESPACE' (n8n + Redis + PostgreSQL)..."
kubectl delete namespace $NAMESPACE --ignore-not-found

echo ""
echo "==> Ambiente destruido com sucesso!"
