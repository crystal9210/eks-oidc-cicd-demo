# EKS×Istio× マイクロサービス CI/CD プロジェクト 完全ディレクトリ構造・責務ドキュメント

このドキュメントは、**現場で即運用できるレベル**で、
「EKS×Istio× マイクロサービス ×CI/CD× セキュリティ自動化 × 認証認可 ×DB 冗長化」
を**一切省略せず**、各ファイル・ディレクトリの責務まで**具体的かつ詳細に**記述したものです。

## 1. 完成系ディレクトリ構造（全体像）

```
project-root/
├── .github/
│   └── workflows/
│       └── ci-cd.yaml
├── cicd/
│   ├── argocd-apps/
│   │   └── user-service-app.yaml
│   ├── opa-policies/
│   │   └── require-label.rego
│   └── README.md
├── docs/
│   ├── architecture.md
│   ├── api/
│   │   └── openapi.yaml
│   ├── security.md
│   ├── db.md
│   ├── operations.md
│   └── README.md
├── infra/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── helm/
│   │   └── istio/
│   │       └── values.yaml
│   └── k8s/
│       ├── user-service/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── hpa.yaml
│       │   └── pdb.yaml
│       ├── istio/
│       │   ├── gateway.yaml
│       │   ├── virtualservice.yaml
│       │   ├── destinationrule.yaml
│       │   └── authorizationpolicy.yaml
│       ├── db/
│       │   ├── rds-operator.yaml
│       │   └── secret.yaml
│       └── monitoring/
│           ├── prometheus.yaml
│           ├── grafana.yaml
│           └── kiali.yaml
├── src/
│   ├── user-service/
│   │   ├── main.go
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   └── README.md
│   ├── video-service/
│   │   ├── app.js
│   │   ├── Dockerfile
│   │   └── README.md
│   └── chat-service/
│       ├── main.py
│       ├── Dockerfile
│       └── README.md
├── scripts/
│   ├── db-migrate.sh
│   ├── deploy.sh
│   └── cleanup.sh
├── .env.example
├── README.md
└── Makefile
```

## 2. 各ディレクトリ・ファイルの責務（詳細解説）

### .github/workflows/ci-cd.yaml

-   **責務**:
    GitHub Actions による CI/CD パイプラインの定義。
    -   PR 時：Lint, UnitTest, Build, Trivy/Snyk/kube-linter/OPA によるセキュリティ・品質チェック
    -   main マージ時：ECR プッシュ →ArgoCD で EKS に自動デプロイ

### cicd/argocd-apps/user-service-app.yaml

-   **責務**:
    ArgoCD で管理する Kubernetes アプリケーション（user-service）の定義。
    -   ソースリポジトリ、K8s マニフェストパス、デプロイ先 namespace、sync ポリシーなどを記述

### cicd/opa-policies/require-label.rego

-   **責務**:
    OPA（Open Policy Agent）による Kubernetes リソースの Admission 制約ポリシー。
    -   例：全 Deployment に`team`ラベル必須、などのガバナンス強制

### docs/

-   **責務**:
    プロジェクトのアーキテクチャ、API 仕様、セキュリティ、DB 設計、運用 Runbook などのドキュメント群
    -   `architecture.md`: システム全体構成図・設計思想
    -   `api/openapi.yaml`: OpenAPI/Swagger による API 仕様
    -   `security.md`: 認証認可、脆弱性対策、権限設計
    -   `db.md`: DB スキーマ、冗長化設計、バックアップ戦略
    -   `operations.md`: 運用手順、障害対応、SLA/SLO
    -   各種 README: サブディレクトリごとの補足

### infra/terraform/

-   **責務**:
    AWS リソース（VPC, EKS, RDS, ALB, ACM, IAM, S3, CloudWatch, OIDC 他）の IaC 管理
    -   `main.tf`: 主要リソース定義
    -   `variables.tf`: 変数定義
    -   `outputs.tf`: 出力値定義
    -   `README.md`: IaC 運用ガイド

### infra/helm/

-   **責務**:
    Istio や Prometheus, Grafana 等のミドルウェアを Helm でデプロイするための設定
    -   `istio/values.yaml`: Istio のカスタム設定

### infra/k8s/

-   **責務**:
    各種 Kubernetes マニフェスト（サービス単位でサブディレクトリ分割）
    -   `user-service/`: Deployment, Service, Ingress, HPA, PDB 等
    -   `istio/`: Gateway, VirtualService, DestinationRule, AuthorizationPolicy 等
    -   `db/`: DB Operator、Secret（DB 認証情報）、PersistentVolume 等
    -   `monitoring/`: Prometheus, Grafana, Kiali 等の監視用マニフェスト

### src/

-   **責務**:
    各マイクロサービスのアプリ実装＋ Dockerfile
    -   `user-service/`: Go 実装例
    -   `video-service/`: Node.js 実装例
    -   `chat-service/`: Python 実装例
    -   各サービスごとに README, テスト、CI 用設定も配置

### scripts/

-   **責務**:
    DB マイグレーション、デプロイ補助、クリーンアップ等の運用用スクリプト

### .env.example

-   **責務**:
    ローカル開発・CI/CD 用の環境変数テンプレート

### README.md

-   **責務**:
    プロジェクト全体の概要、セットアップ手順、開発フロー、運用ルール等

### Makefile

-   **責務**:
    開発・デプロイ・テスト等の標準化コマンド集（例：`make build`, `make test`, `make deploy`）

## 3. 主要ファイルの具体例（抜粋）

### .github/workflows/ci-cd.yaml（CI/CD パイプライン）

```yaml
name: CI/CD Pipeline

on:
    pull_request:
        branches: [main]
    push:
        branches: [main]

env:
    AWS_REGION: ap-northeast-1
    ECR_REPOSITORY: user-service
    IMAGE_TAG: ${{ github.sha }}

jobs:
    build-test:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - name: Lint
              run: go vet ./...
            - name: Test
              run: go test -v ./...
            - name: Build Docker image
              run: docker build -t $ECR_REPOSITORY:$IMAGE_TAG src/user-service
            - name: Trivy Scan
              uses: aquasecurity/trivy-action@v0.11.2
              with:
                  image-ref: ${{ env.ECR_REPOSITORY }}:${{ env.IMAGE_TAG }}
            - name: Snyk Scan
              uses: snyk/actions/docker@v3
              with:
                  image: ${{ env.ECR_REPOSITORY }}:${{ env.IMAGE_TAG }}
              env:
                  SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
            - name: KubeLinter Scan
              uses: stackrox/kube-linter-action@v1
              with:
                  manifests: infra/k8s/
            - name: OPA Policy Check
              uses: open-policy-agent/opa-github-action@v2
              with:
                  files: cicd/opa-policies/require-label.rego
            - name: Configure AWS credentials
              uses: aws-actions/configure-aws-credentials@v4
              with:
                  aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
                  aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
                  aws-region: ${{ env.AWS_REGION }}
            - name: Login to Amazon ECR
              id: login-ecr
              uses: aws-actions/amazon-ecr-login@v2
            - name: Push to ECR
              if: github.event_name == 'push'
              run: |
                  docker tag $ECR_REPOSITORY:$IMAGE_TAG ${{ steps.login-ecr.outputs.registry }}/$ECR_REPOSITORY:$IMAGE_TAG
                  docker push ${{ steps.login-ecr.outputs.registry }}/$ECR_REPOSITORY:$IMAGE_TAG

    deploy:
        needs: build-test
        if: github.event_name == 'push'
        runs-on: ubuntu-latest
        steps:
            - name: ArgoCD Deploy
              uses: actions/checkout@v4
            - name: ArgoCD CLI Login
              run: |
                  argocd login $ARGOCD_SERVER --username $ARGOCD_USERNAME --password $ARGOCD_PASSWORD --insecure
              env:
                  ARGOCD_SERVER: ${{ secrets.ARGOCD_SERVER }}
                  ARGOCD_USERNAME: ${{ secrets.ARGOCD_USERNAME }}
                  ARGOCD_PASSWORD: ${{ secrets.ARGOCD_PASSWORD }}
            - name: ArgoCD Sync App
              run: |
                  argocd app sync user-service
```

### cicd/opa-policies/require-label.rego（OPA ポリシー例）

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Deployment"
  not input.request.object.metadata.labels["team"]
  msg := "All deployments must have a 'team' label"
}
```

### infra/k8s/user-service/deployment.yaml（K8s デプロイ例）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  labels:
    app: user-service
    team: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
        team: backend
    spec:
      containers:
      - name: user-service
        image: :
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: "1"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "128Mi"
```

### infra/k8s/istio/gateway.yaml（Istio Gateway 例）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
    name: user-service-gateway
    namespace: prod
spec:
    selector:
        istio: ingressgateway
    servers:
        - port:
              number: 80
              name: http
              protocol: HTTP
          hosts:
              - "user.example.com"
```

### infra/terraform/main.tf（Terraform 例）

```hcl
module "vpc" { ... }
module "eks" { ... }
module "rds" { ... }
module "alb" { ... }
# 各種リソースのIaC管理
```

## 4. GitHub/CI/CD/クラウド側の設定

-   **GitHub Secrets**

    -   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`（ECR/EKS 用 IAM ユーザー）
    -   `SNYK_TOKEN`（Snyk 登録）
    -   `ARGOCD_SERVER`/`ARGOCD_USERNAME`/`ARGOCD_PASSWORD`（ArgoCD 管理用）

-   **ECR リポジトリ作成**

    ```
    aws ecr create-repository --repository-name user-service --region ap-northeast-1
    ```

-   **ArgoCD インストール＆アプリ登録**

    -   EKS 上に ArgoCD
    -   `argocd app create`で cicd/argocd-apps/の yaml を登録

-   **Snyk/Trivy/kube-linter/OPA は GitHub Actions で自動実行**

## 5. 補足・運用上の注意

-   **各サービスごとに src/・infra/k8s/・cicd/以下を分割管理することで拡張性・保守性を最大化**
-   **ドキュメントは必ず最新化し、運用 Runbook・障害対応・SLA/SLO も明記**
-   **DB は RDS/Aurora のマルチ AZ 冗長化＋ K8s シークレット連携**
-   **監視は Prometheus/Grafana/Loki/Kiali/CloudWatch 等を組み合わせて多層防御**
-   **CI/CD はセキュリティ自動化・品質保証・自動デプロイまで一気通貫**

## 6. まとめ

-   **このディレクトリ構成・ファイル責務・CI/CD 設計をベースに、世界最高峰レベルのクラウドネイティブ開発・運用が可能**
-   **全ての工程で「なぜ必要か」「どこで管理するか」「どう自動化するか」を明確化**
-   **各種領域(DB 冗長化、認証認可、運用 Runbook、監視設計等)は個別に詳細設計としてドキュメントに記述(docs/\*)**
