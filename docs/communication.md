# アプリ通信経路・パターンの詳細設計書（認証・認可・スケール対応）

## 1. システム全体構成図（テキスト表現）

```

[Client(Browser/App)]
      │
      │ HTTPS
      ▼
[ALB (AWS Application Load Balancer)]
      │
      │ HTTPS (ACM証明書)
      ▼
[istio-ingressgateway (EKS, Istio)]
      │
      │ mTLS (Istio)
      ▼
[Istio Gateway]
      │
      │ HTTP/mTLS (Istio VirtualService, DestinationRule)
      ▼
[各マイクロサービス (user-service, video-service, chat-service)]
      │
      │ DB接続（RDS/Aurora, SecretsManager経由で認証情報取得, マルチAZ冗長）
      ▼
[DB (RDS/Aurora)]
```

## 2. 通信経路・パターン詳細

### 2.1 外部からのリクエストフロー

1. **クライアント（Web/モバイル）**

    - HTTPS で ALB にアクセス（例: `https://user.example.com/api/v1/users`）

2. **ALB (AWS Application Load Balancer)**

    - ACM 証明書で TLS 終端
    - 受けたリクエストを EKS 内の istio-ingressgateway へ転送
    - WAF で L7/L4 ファイアウォール可能

3. **istio-ingressgateway**

    - Istio Gateway リソースで受信
    - VirtualService でホスト名・パスごとに各サービスへルーティング
    - 例: `/api/v1/users` → user-service, `/api/v1/videos` → video-service

4. **Istio mTLS 通信**

    - ingressgateway と各サービス間は**必ず mTLS（双方向 TLS）**で暗号化
    - サービス間通信も**mTLS 強制（STRICT）**

5. **各マイクロサービス**

    - user-service, video-service, chat-service 等
    - 認証認可（JWT/OAuth2/OIDC）を**Envoy/Istio で自動検証**
    - RBAC/ABAC（Istio AuthorizationPolicy/OPA）でサービス間アクセス制御
    - 必要に応じて外部 API や DB へアクセス

6. **DB 接続**
    - DB は RDS/Aurora 等のマルチ AZ 冗長構成
    - DB 認証情報は Kubernetes Secret や AWS Secrets Manager 連携
    - DB 通信も SSL/TLS で暗号化

### 2.2 サービス間通信パターン

#### ① REST/gRPC API

-   サービス A → サービス B への通信は必ず mTLS
-   Istio VirtualService/DestinationRule でリトライ・タイムアウト・サーキットブレーカー制御
-   AuthorizationPolicy で呼び出し元の認可制御

#### ② 非同期メッセージング

-   必要に応じて SQS/Kafka/PubSub 等を利用
-   サービス間の「疎結合」「イベント駆動」を実現

### 2.3 認証・認可の設計

#### 認証（Authentication）

-   **外部からの API リクエストは全て JWT（OIDC/OAuth2）必須**
    -   Cognito/Auth0/Google 等の IdP で発行
    -   Istio Envoy で JWT 自動検証（`RequestAuthentication`リソースを利用）
-   **サービス間通信も JWT 伝播（必要に応じて）**

#### 認可（Authorization）

-   **Istio AuthorizationPolicy で RBAC/ABAC を実現**
    -   例: user-service のみ video-service の管理 API にアクセス可能
    -   JWT の claim（role, sub, aud 等）に応じて細かく制御
-   **OPA/Gatekeeper で Kubernetes リソースの Admission 制約**
    -   例: team ラベル必須、特権 Pod 禁止

### 2.4 スケール・可用性設計

-   **ALB は AWS の自動スケール**
-   **istio-ingressgateway は Deployment で replica 数を HPA で自動調整**
-   **各マイクロサービスも HPA で負荷に応じて Pod 数を自動増減**
-   **DB（RDS/Aurora）はマルチ AZ 冗長＋リードレプリカ構成**
-   **PodDisruptionBudget（PDB）で最小稼働数を保証**
-   **Kubernetes Cluster Autoscaler でノード自動増減**

### 2.5 監視・ロギング・可観測性

-   **Prometheus でメトリクス収集、Grafana で可視化**
-   **Loki/Fluentd/CloudWatch Logs でログ集約**
-   **Jaeger で分散トレーシング、Kiali で Istio 通信可視化**
-   **Alertmanager/CloudWatch で障害検知・通知**

## 3. 具体的な通信パターン例

### 3.1 ユーザー新規登録 API のリクエストフロー

1. クライアント → `https://user.example.com/api/v1/users`（ALB, HTTPS）
2. ALB → istio-ingressgateway（HTTPS, ACM 証明書）
3. istio-ingressgateway → user-service（mTLS, JWT 認証）
4. user-service → RDS（TLS, Secret 経由認証）
5. レスポンスが逆経路で返る

### 3.2 サービス間通信（user-service → video-service）

1. user-service が video-service の API を呼ぶ（mTLS, JWT 付き）
2. Istio VirtualService でルーティング
3. AuthorizationPolicy で認可判定
4. video-service が処理し、レスポンスを返す

## 4. 参考：主要 Kubernetes/Istio リソースの役割

-   **Gateway**: ALB からの通信を受ける Istio の入口
-   **VirtualService**: パス/ホストごとに各サービスへ振り分け
-   **DestinationRule**: 通信先の mTLS や負荷分散ポリシー
-   **AuthorizationPolicy**: サービス間・外部からの認可制御
-   **RequestAuthentication**: JWT 等の認証検証
-   **HPA**: Pod 自動スケール
-   **PDB**: Pod の最小稼働数保証

## 5. まとめ

-   **全通信経路は必ず TLS/mTLS で暗号化**
-   **認証は JWT（OIDC/OAuth2）、認可は Istio/OPA で多層防御**
-   **ALB, Istio, 各サービス、DB すべてが高可用性・スケールアウト設計**
-   **監視・ロギング・可観測性も最初から組み込み**
-   **Kubernetes/Istio リソースで全ての制御を「コード化」し、CI/CD で自動適用**

**この設計をベースに、各サービスの API 設計・DB スキーマ・CI/CD・運用 Runbook まで全て拡張可能です。
さらに詳細なサンプルや具体的な Kubernetes/Istio マニフェスト例もご要望に応じてご案内します。**

# 完全実装ガイド：EKS×Istio× マイクロサービス CI/CD プロジェクト

**（一切省略なし・この通りに進めれば完成するレベル）**

## 0. 前提・開発哲学

-   **徹底的な文書化・品質保証・段階的なマイルストーン・自動化・セキュリティ重視**[1][2]
-   **Rust 実装の場合もベストプラクティス・明確なコード構成を徹底**[3]
-   **API や CI/CD は完全なコード例を提示し、統合性を担保**[4]
-   **GitHub Actions を中心とした体系的なワークフロー設計**[5][6]
-   **全体を通して、ディレクトリ構造・責務・通信・認証認可・スケール・監視・運用まで一切省略せず記述**

## 1. ディレクトリ構造（完成形）

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
│   │   ├── main.rs
│   │   ├── Dockerfile
│   │   ├── Cargo.toml
│   │   ├── tests/
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

## 2. 通信経路・認証認可・スケール設計（詳細）

### 2.1 外部 → 内部通信フロー

1. **Client**
    - HTTPS で ALB へアクセス
2. **ALB**
    - ACM 証明書で TLS 終端、WAF で L7/L4 検査
    - EKS 上の istio-ingressgateway に転送
3. **istio-ingressgateway**
    - Istio Gateway で受信、VirtualService でルーティング
    - JWT/OIDC 認証（RequestAuthentication）を自動検証
    - mTLS で各サービスへ
4. **各マイクロサービス**
    - RBAC/ABAC（AuthorizationPolicy/OPA）で認可
    - サービス間通信も mTLS 強制
    - DB アクセスは Secret 経由で認証情報取得、TLS 接続
5. **DB**
    - RDS/Aurora、マルチ AZ 冗長、TLS

### 2.2 サービス間通信パターン

-   **REST/gRPC**
    -   必ず mTLS
    -   Istio VirtualService/DestinationRule でリトライ・タイムアウト・CB
-   **非同期メッセージ**
    -   SQS/Kafka/CloudPubSub
    -   Event-driven 設計

### 2.3 認証認可

-   **認証**
    -   外部 API は JWT 必須（Cognito/Auth0/Google 発行）
    -   Istio の RequestAuthentication で自動検証
-   **認可**
    -   Istio AuthorizationPolicy で RBAC/ABAC
    -   OPA/Gatekeeper で K8s リソース制約

### 2.4 スケール・可用性

-   **ALB/EKS/istio-ingressgateway/各サービス：HPA で自動スケール**
-   **DB：マルチ AZ ＋リードレプリカ**
-   **PodDisruptionBudget で可用性担保**
-   **Cluster Autoscaler でノード自動増減**

## 3. 各ディレクトリ・ファイルの責務（完全解説）

### .github/workflows/ci-cd.yaml

-   **CI/CD パイプライン定義**
    -   PR: Lint, UnitTest, Build, Trivy/Snyk/kube-linter/OPA
    -   main: ECR プッシュ →ArgoCD でデプロイ

### cicd/argocd-apps/user-service-app.yaml

-   **ArgoCD アプリ定義**
    -   Git リポジトリ、K8s マニフェストパス、デプロイ先、syncPolicy

### cicd/opa-policies/require-label.rego

-   **OPA ポリシー**
    -   例: Deployment には必ず`team`ラベル

### docs/

-   **アーキ・API・セキュリティ・DB・運用 Runbook 等の全設計ドキュメント**

### infra/terraform/

-   **AWS リソースの IaC 管理**
    -   VPC/EKS/ALB/RDS/ACM/IAM/S3/CloudWatch/SecretsManager/OIDC

### infra/helm/

-   **Helm チャートでミドルウェア（Istio 等）をデプロイ**

### infra/k8s/

-   **Kubernetes マニフェスト管理**
    -   サービスごとに Deployment/Service/Ingress/HPA/PDB
    -   Istio Gateway/VirtualService/DestinationRule/AuthorizationPolicy
    -   DB（RDS Operator, Secret）
    -   監視（Prometheus/Grafana/Kiali）

### src/

-   **各マイクロサービスのアプリ実装**
    -   Rust/Go/Node/Python 等
    -   Dockerfile, テスト, README

### scripts/

-   **DB マイグレーション・デプロイ・クリーンアップ等の補助スクリプト**

### .env.example

-   **環境変数テンプレート**

### Makefile

-   **標準化コマンド集（build/test/deploy/clean 等）**

## 4. 主要ファイルの実装例（抜粋・完全版）

### .github/workflows/ci-cd.yaml

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

            - name: Set up Rust
              uses: actions/setup-rust@v1
              with:
                  rust-version: "1.77"
            - name: Lint
              run: cargo clippy --all-targets --all-features -- -D warnings
              working-directory: src/user-service
            - name: Test
              run: cargo test --all
              working-directory: src/user-service

            - name: Build Docker image
              run: docker build -t $ECR_REPOSITORY:$IMAGE_TAG .
              working-directory: src/user-service

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

### infra/k8s/user-service/deployment.yaml

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
        envFrom:
        - secretRef:
            name: user-service-secret
        resources:
          limits:
            cpu: "1"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "128Mi"
```

### infra/k8s/istio/gateway.yaml

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

### infra/k8s/istio/authorizationpolicy.yaml

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
    name: user-service-authz
    namespace: prod
spec:
    selector:
        matchLabels:
            app: user-service
    action: ALLOW
    rules:
        - from:
              - source:
                    requestPrincipals: ["*"] # JWT認証済みのみ許可
          to:
              - operation:
                    methods: ["GET", "POST", "PUT", "DELETE"]
```

### cicd/opa-policies/require-label.rego

```rego
package kubernetes.admission

deny[msg] {
  input.request.kind.kind == "Deployment"
  not input.request.object.metadata.labels["team"]
  msg := "All deployments must have a 'team' label"
}
```

### infra/k8s/db/secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: user-service-secret
    namespace: prod
type: Opaque
data:
    DB_USER:
    DB_PASS:
    DB_HOST:
    DB_NAME:
```

## 5. 運用・監視・セキュリティ

-   **Prometheus/Grafana/Loki/Kiali/Jaeger**で監視・可観測性
-   **CloudWatch/GuardDuty/SecurityHub**で AWS 全体の監査・脅威検知
-   **PodSecurityPolicy/Admission Controller で Pod 特権制御**
-   **定期的な脆弱性診断・自動テスト・E2E テスト**

## 6. 開発・運用フロー

1. **新機能開発**：src/以下で実装 → テスト →PR
2. **CI/CD**：自動 Lint/Test/Build/セキュリティスキャン
3. **main マージで ECR/ArgoCD/EKS 自動デプロイ**
4. **監視・ログ・トレーシングで運用監視**
5. **障害時は docs/operations.md の Runbook に従い対応**

## 7. まとめ

-   **この設計・実装を完全に遵守すれば、世界最高峰水準の EKS×Istio× マイクロサービス基盤が完成します**
-   **すべての責務・設計意図・コード例を明示し、運用まで一気通貫でカバー**
-   **さらに詳細なサンプルやサービス追加、DB 冗長化、CI/CD 拡張などもご要望に応じて随時案内可能**

**このガイドをそのままプロジェクトの基盤として採用し、各サービス・環境ごとに拡張・最適化してください。**

[1] projects.requirement_management
[2] projects.development_process
[3] programming.rust_implementation
[4] programming.code_integration
[5] preferences.development_workflow
[6] projects.development_workflow
