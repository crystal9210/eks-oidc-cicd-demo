#!/bin/bash
# NOTES: This script is for initializing dir structure (file systems' structure). pls execute below in your shell env at the root dir in your pj.
# commands
# 1. chmod +x create_project_structure.sh
# 2. ./create_project_structure.sh

set -eu

# ディレクトリとファイルのリスト
entries=(
  ".github/"
  ".github/workflows/"
  ".github/workflows/ci-cd.yaml"
  "cicd/"
  "cicd/argocd-apps/"
  "cicd/argocd-apps/user-service-app.yaml"
  "cicd/opa-policies/"
  "cicd/opa-policies/require-label.rego"
  "cicd/README.md"
  "docs/"
  "docs/architecture.md"
  "docs/api/"
  "docs/api/openapi.yaml"
  "docs/security.md"
  "docs/db.md"
  "docs/operations.md"
  "docs/README.md"
  "infra/"
  "infra/terraform/"
  "infra/terraform/main.tf"
  "infra/terraform/variables.tf"
  "infra/terraform/outputs.tf"
  "infra/terraform/README.md"
  "infra/helm/"
  "infra/helm/istio/"
  "infra/helm/istio/values.yaml"
  "infra/k8s/"
  "infra/k8s/user-service/"
  "infra/k8s/user-service/deployment.yaml"
  "infra/k8s/user-service/service.yaml"
  "infra/k8s/user-service/ingress.yaml"
  "infra/k8s/user-service/hpa.yaml"
  "infra/k8s/user-service/pdb.yaml"
  "infra/k8s/istio/"
  "infra/k8s/istio/gateway.yaml"
  "infra/k8s/istio/virtualservice.yaml"
  "infra/k8s/istio/destinationrule.yaml"
  "infra/k8s/istio/authorizationpolicy.yaml"
  "infra/k8s/db/"
  "infra/k8s/db/rds-operator.yaml"
  "infra/k8s/db/secret.yaml"
  "infra/k8s/monitoring/"
  "infra/k8s/monitoring/prometheus.yaml"
  "infra/k8s/monitoring/grafana.yaml"
  "infra/k8s/monitoring/kiali.yaml"
  "src/"
  "src/user-service/"
  "src/user-service/main.go"
  "src/user-service/Dockerfile"
  "src/user-service/go.mod"
  "src/user-service/README.md"
  "src/video-service/"
  "src/video-service/app.js"
  "src/video-service/Dockerfile"
  "src/video-service/README.md"
  "src/chat-service/"
  "src/chat-service/main.py"
  "src/chat-service/Dockerfile"
  "src/chat-service/README.md"
  "scripts/"
  "scripts/db-migrate.sh"
  "scripts/deploy.sh"
  "scripts/cleanup.sh"
  ".env.example"
  "README.md"
  "Makefile"
)

for entry in "${entries[@]}"; do
  # ディレクトリの場合
  if [[ "$entry" =~ /$ ]]; then
    if [ ! -d "$entry" ]; then
      echo "Creating directory: $entry"
      mkdir -p "$entry"
    fi
  else
    dir=$(dirname "$entry")
    if [ ! -d "$dir" ]; then
      echo "Creating parent directory: $dir"
      mkdir -p "$dir"
    fi
    if [ ! -f "$entry" ]; then
      echo "Creating file: $entry"
      touch "$entry"
    fi
  fi
done

echo "プロジェクト構造の作成が完了しました。"
