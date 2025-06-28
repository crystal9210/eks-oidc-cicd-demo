# EKS×Istio× マイクロサービス CI/CD PJ ディレクトリ構造・責務 Doc

このドキュメントは、**現場運用レベル**で
「EKS×Istio× マイクロサービス ×CI/CD× セキュリティ自動化 × 認証認可 ×DB 冗長化 × 監視 × テスト × ガバナンス」
を、**各ファイル・ディレクトリ・サービスの責務まで具体的かつ詳細に**記述したものです。

## 0. PJ 全体像・設計思想

-   EKS: AWS マネージド Kubernetes。可用性・スケール・IAM 統合。

-   Istio: サービスメッシュ。mTLS/認証認可/トラフィック制御/可観測性/レートリミット/カナリア/サーキットブレーカー。

-   ALB: L7 ロードバランサ。外部公開・HTTPS 終端・WAF 連携。

-   ArgoCD: GitOps デプロイ。宣言的運用・自動同期・ロールバック。

-   OPA/Gatekeeper: ポリシー強制・Admission 制御・ガバナンス。

-   Prometheus/Grafana/Kiali/CloudWatch: 監視・メトリクス・ダッシュボード・トレーシング・アラート。

-   trivy/kube-bench/kube-linter: セキュリティ自動化・CIS 準拠・静的解析。

-   Terraform/Helm: IaC。AWS リソース・ミドルウェア・K8s リソースのコード管理。

-   Go/Node.js/Python: Polyglot マイクロサービス。各サービスごとに責務分離・API 設計・テスト分離。

-   CI/CD: PR 時に全自動 Lint/テスト/セキュリティ/ポリシーチェック、本番は ArgoCD で自動デプロイ。

## 1. ディレクトリ構造

```
eks-oidc-cicd-demo/
├── .github/
│   └── workflows/
│       ├── ci-cd.yaml
│       ├── lint-go.yaml
│       ├── lint-node.yaml
│       ├── lint-python.yaml
│       ├── e2e-playwright.yaml
│       ├── kube-bench.yaml
│       ├── kube-linter.yaml
│       ├── trivy.yaml
│       └── policy-gatekeeper.yaml
├── cicd/
│   ├── argocd-apps/
│   │   ├── user-service-app.yaml
│   │   ├── video-service-app.yaml
│   │   └── chat-service-app.yaml
│   ├── opa-policies/
│   │   ├── require-label.rego
│   │   └── deny-privileged.rego
│   ├── gatekeeper-constraints/
│   │   ├── require-label.yaml
│   │   └── deny-privileged.yaml
│   └── README.md
├── docs/
│   ├── architecture.md
│   ├── api/
│   │   ├── openapi-user.yaml
│   │   ├── openapi-video.yaml
│   │   └── openapi-chat.yaml
│   ├── security.md
│   ├── db.md
│   ├── operations.md
│   ├── cicd.md
│   ├── monitoring.md
│   └── README.md
├── infra/
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── provider.tf
│   │   ├── eks.tf
│   │   ├── alb.tf
│   │   ├── rds.tf
│   │   ├── iam.tf
│   │   ├── s3.tf
│   │   ├── cloudwatch.tf
│   │   └── README.md
│   ├── helm/
│   │   ├── istio/
│   │   │   └── values.yaml
│   │   ├── prometheus/
│   │   │   └── values.yaml
│   │   ├── grafana/
│   │   │   └── values.yaml
│   │   └── gatekeeper/
│   │       └── values.yaml
│   └── k8s/
│       ├── user-service/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── hpa.yaml
│       │   ├── pdb.yaml
│       │   └── secret.yaml
│       ├── video-service/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── hpa.yaml
│       │   ├── pdb.yaml
│       │   └── secret.yaml
│       ├── chat-service/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── hpa.yaml
│       │   ├── pdb.yaml
│       │   └── secret.yaml
│       ├── istio/
│       │   ├── gateway.yaml
│       │   ├── virtualservice.yaml
│       │   ├── destinationrule.yaml
│       │   ├── authorizationpolicy.yaml
│       │   └── requestauthentication.yaml
│       ├── db/
│       │   ├── rds-operator.yaml
│       │   └── secret.yaml
│       └── monitoring/
│           ├── prometheus.yaml
│           ├── grafana.yaml
│           ├── kiali.yaml
│           └── cloudwatch-agent.yaml
├── src/
│   ├── user-service/
│   │   ├── main.go
│   │   ├── Dockerfile
│   │   ├── go.mod
│   │   ├── README.md
│   │   └── tests/
│   │       ├── unit/
│   │       │   ├── user_handler_test.go
│   │       │   └── user_model_test.go
│   │       ├── integration/
│   │       │   └── user_db_test.go
│   │       └── e2e/
│   │           └── user_api_test.go
│   ├── video-service/
│   │   ├── app.js
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── README.md
│   │   └── tests/
│   │       ├── unit/
│   │       │   ├── videoController.test.js
│   │       │   └── videoModel.test.js
│   │       ├── integration/
│   │       │   └── videoDb.test.js
│   │       └── e2e/
│   │           └── videoApi.test.js
│   └── chat-service/
│       ├── main.py
│       ├── Dockerfile
│       ├── requirements.txt
│       ├── README.md
│       └── tests/
│           ├── unit/
│           │   ├── test_chat_handler.py
│           │   └── test_chat_model.py
│           ├── integration/
│           │   └── test_chat_db.py
│           └── e2e/
│               └── test_chat_api.py
├── scripts/
│   ├── db-migrate.sh
│   ├── deploy.sh
│   └── cleanup.sh
├── .env.example
├── README.md
└── Makefile
```

## 2. サブディレクトリ・ファイル責務

### .github/workflows/

-   **ci-cd.yaml**

    -   **責務**:
        全サービス共通の CI/CD パイプライン。
        -   PR 時：全サービスの Lint（golangci-lint, eslint, flake8）、ユニットテスト（go test, jest, pytest）、ビルド、Trivy/Snyk によるイメージ脆弱性スキャン、kube-linter による K8s マニフェスト静的解析、OPA によるポリシーチェック。
        -   main マージ時：ECR への Docker イメージプッシュ、ArgoCD CLI による EKS 本番環境への自動デプロイ。
    -   **使い所**:
        -   PR 時に品質・セキュリティ担保。
        -   本番反映時は GitOps で自動化・安全・即時反映。
        -   失敗時は Slack 通知や GitHub Status で即時可視化。
    -   **運用上のポイント**:
        -   各サービスの追加時はここにビルド・テスト・デプロイステップを必ず追加。
        -   Secrets（AWS/ECR/ArgoCD/Snyk トークン等）は GitHub Secrets で集中管理。

-   **lint-go.yaml**

    -   **責務**: Go コードの静的解析（golangci-lint）、ユニットテスト（go test）。
    -   **使い所**:
        -   Go サービス追加時に個別で高速 Lint/Test を回せる。
    -   **運用上のポイント**:
        -   go.mod の依存追加時や CI 失敗時はここで原因特定。

-   **lint-node.yaml**

    -   **責務**: Node.js コードの静的解析（eslint）、ユニットテスト（jest）。
    -   **使い所**:
        -   Node.js サービス追加時や ESLint ルール改定時の検証。
    -   **運用上のポイント**:
        -   package.json のスクリプト・依存管理もここで確認。

-   **lint-python.yaml**

    -   **責務**: Python コードの静的解析（flake8）、ユニットテスト（pytest）。
    -   **使い所**:
        -   Python サービス追加時や PEP8/型安全性の担保。
    -   **運用上のポイント**:
        -   requirements.txt の依存追加・バージョン更新時はここで検証。

-   **e2e-playwright.yaml**

    -   **責務**: Playwright による E2E/API テスト。
        -   フロントエンドや API の統合動作、サービス間の実際の API フロー検証。
    -   **使い所**:
        -   複数サービス横断（例: ユーザー登録 → 動画アップロード → チャット送信など）の一連の流れを自動検証。
    -   **運用上のポイント**:
        -   新規 API 追加・仕様変更時は必ず E2E シナリオも追加。

-   **kube-bench.yaml**

    -   **責務**: kube-bench による EKS ノードの CIS ベンチマーク自動チェック。
    -   **使い所**:
        -   クラスタのセキュリティレベル維持・向上。
        -   ノード追加・K8s バージョンアップ時の自動チェック。
    -   **運用上のポイント**:
        -   重大な CIS 違反は CI/CD で Fail させ、運用 Runbook に対応手順を記載。

-   **kube-linter.yaml**

    -   **責務**: kube-linter で K8s マニフェストの静的解析（Best Practice 違反検出）。
    -   **使い所**:
        -   マニフェストの誤り・危険な設定（例: Privileged, HostPath, No Resource Requests 等）を早期検出。
    -   **運用上のポイント**:
        -   新しい K8s リソース追加時は必ず CI で検証。

-   **trivy.yaml**

    -   **責務**: trivy で Docker イメージの脆弱性スキャン。
    -   **使い所**:
        -   各サービスのイメージビルド時に CVE 漏れを即検知。
    -   **運用上のポイント**:
        -   重大 CVE は CI/CD で Fail。Base イメージ更新時も必ず再スキャン。

-   **policy-gatekeeper.yaml**
    -   **責務**: OPA/Gatekeeper の Rego ポリシー・Constraint のテスト。
    -   **使い所**:
        -   新規ポリシー追加時や運用ポリシー変更時の自動検証。
    -   **運用上のポイント**:
        -   本番適用前に必ず CI でシミュレーション。

### cicd/

-   **argocd-apps/**

    -   **責務**:
        各サービスの ArgoCD Application リソース（YAML）を管理。
        -   Git リポジトリ URL、K8s マニフェストパス、デプロイ先 namespace、同期ポリシー（自動/手動）、Prune/自動修復設定など。
    -   **使い所**:
        -   GitOps 運用の基点。
        -   dev/stg/prd など複数環境へのマルチデプロイもここで管理。
    -   **運用上のポイント**:
        -   新サービス追加時や環境追加時は必ずここを更新。
        -   ArgoCD UI/CLI で Sync/Prune/History 管理。

-   **opa-policies/**

    -   **責務**:
        OPA（Open Policy Agent）用 Rego ファイル。
        -   例：require-label.rego（全 Deployment に team ラベル必須）、deny-privileged.rego（特権 Pod 禁止）、リソース制限等。
    -   **使い所**:
        -   Admission 制御で K8s リソースのガバナンス強制。
    -   **運用上のポイント**:
        -   ポリシー違反時の CI/CD Fail や Slack 通知連携もここで設計。

-   **gatekeeper-constraints/**

    -   **責務**:
        Gatekeeper の Constraint YAML。
        -   Rego ポリシーを K8s クラスタへ適用するための宣言（ConstraintTemplate/Constraint）。
    -   **使い所**:
        -   本番クラスタへのガバナンス強制。
    -   **運用上のポイント**:
        -   運用ポリシー変更時は必ず CI/CD でテスト後、本番適用。

-   **README.md**
    -   **責務**:
        CI/CD・ポリシー運用の説明、トラブル時の手順、ロールバック方法、CI/CD 失敗時の連絡先など。

### docs/

-   **architecture.md**

    -   **責務**:
        システム全体図（テキスト＋図）、各コンポーネントの役割、ネットワーク構成（VPC/ALB/EKS/DB）、冗長化・スケール設計、通信パターン（REST/gRPC/イベント）、セキュリティ設計（mTLS/認証認可/ゼロトラスト）、マルチクラスタ/マルチメッシュ設計。
    -   **使い所**:
        -   新規開発者・運用者のオンボーディング、障害時の全体把握、設計レビュー。
    -   **運用上のポイント**:
        -   変更時は必ずアーキ図・設計思想も更新。

-   **api/**

    -   **責務**:
        各サービスの OpenAPI/Swagger 仕様（openapi-user.yaml 等）。
        -   API エンドポイント、リクエスト/レスポンス例、認証方式、エラー設計、バージョン管理。
    -   **使い所**:
        -   API 設計・実装・テスト・外部連携時の参照元。
    -   **運用上のポイント**:
        -   仕様変更時は必ず API ドキュメントも更新。

-   **security.md**

    -   **責務**:
        認証（OIDC/JWT/IdP）、認可（RBAC/ABAC/OPA）、脆弱性対策（CVE 管理/自動スキャン）、権限設計（IAM/K8s RBAC/PodSecurityPolicy/NetworkPolicy）。
    -   **使い所**:
        -   セキュリティレビュー、監査、脆弱性対応計画の基準。
    -   **運用上のポイント**:
        -   セキュリティインシデント発生時の対応手順もここに記載。

-   **db.md**

    -   **責務**:
        DB スキーマ設計（ER 図/テーブル定義/インデックス/制約）、冗長化（RDS/Aurora マルチ AZ, レプリカ, フェイルオーバー）、バックアップ戦略、K8s Secret 連携、障害時の復旧手順。
    -   **使い所**:
        -   DB 障害時の復旧、スキーマ拡張時の設計レビュー。
    -   **運用上のポイント**:
        -   バックアップ/リストア手順、障害発生時の連絡先も必ず明記。

-   **operations.md**

    -   **責務**:
        運用 Runbook（デプロイ/障害対応/証明書更新/スケール/監査）、SLA/SLO、定期運用タスク。
    -   **使い所**:
        -   運用担当者の手順書、障害発生時の初動対応。
    -   **運用上のポイント**:
        -   Runbook は定期的にレビュー・訓練も実施。

-   **cicd.md**

    -   **責務**:
        CI/CD 設計・運用フロー、各種チェック（Lint, Test, Security Scan, Policy Enforcement）、GitHub Actions/ArgoCD/自動デプロイ詳細。
    -   **使い所**:
        -   新規サービス追加時の CI/CD 設計、CI/CD 障害時のトラブルシュート。
    -   **運用上のポイント**:
        -   チェックリスト・失敗時の対応フローも記載。

-   **monitoring.md**

    -   **責務**:
        監視設計（Prometheus, Grafana, CloudWatch, Loki, Kiali, Jaeger）、監視対象・アラートルール・可観測性設計。
    -   **使い所**:
        -   障害検知・アラート設計・運用監視の基準。
    -   **運用上のポイント**:
        -   新規サービス追加時は監視対象・アラートも必ず追加。

-   **README.md**
    -   **責務**:
        docs 配下のドキュメント全体の案内・目次、各ドキュメントの役割・参照先。

### infra/terraform/

-   **main.tf**

    -   **責務**:
        AWS リソース（VPC, EKS, RDS, ALB, ACM, IAM, S3, CloudWatch, OIDC, SecretsManager, SecurityGroup 等）を一元管理。
        -   各種リソースの定義、依存関係、アウトプット管理。
    -   **使い所**:
        -   クラウド基盤の再現性・変更履歴管理。
        -   新規サービス追加や構成変更時の唯一の変更点。
    -   **運用上のポイント**:
        -   terraform plan/apply は必ず PR レビュー後に実施。State ファイルは S3+Lock で管理。

-   **variables.tf/outputs.tf/provider.tf/eks.tf/alb.tf/rds.tf/iam.tf/s3.tf/cloudwatch.tf**

    -   **責務**:
        各 AWS サービスごとに詳細分割管理。変数・出力値・プロバイダー・各リソースの細分化。
    -   **使い所**:
        -   サービス単位・機能単位での独立変更・モジュール化。
    -   **運用上のポイント**:
        -   モジュールバージョン管理、State の分割・統合もここで設計。

-   **README.md**
    -   **責務**:
        IaC 運用ガイド（初期化、Plan/Apply 手順、State 管理、モジュール設計方針、トラブル時の対応）。

### infra/helm/

-   **istio/values.yaml**

    -   **責務**:
        Istio のカスタム設定（Gateway, mTLS, Ingress, Telemetry, SidecarInjection, Pilot 等）。
    -   **使い所**:
        -   Istio アップグレードや設定変更時の唯一の管理点。
    -   **運用上のポイント**:
        -   values.yaml 変更時は必ず helm diff/upgrade で影響確認。

-   **prometheus/values.yaml**

    -   **責務**:
        Prometheus の監視対象、アラートルール、リソース制限等。
    -   **使い所**:
        -   監視対象追加・アラートルール改定時の唯一の管理点。
    -   **運用上のポイント**:
        -   values.yaml 変更後は必ずテストアラートで動作確認。

-   **grafana/values.yaml**

    -   **責務**:
        Grafana のダッシュボード設定、データソース、ユーザー管理。
    -   **使い所**:
        -   ダッシュボードテンプレートの追加・修正時。
    -   **運用上のポイント**:
        -   重要ダッシュボードは JSON エクスポートして Git 管理。

-   **gatekeeper/values.yaml**
    -   **責務**:
        Gatekeeper の ConstraintTemplate, Constraint, Audit 設定。
    -   **使い所**:
        -   ポリシー追加・変更時の唯一の管理点。
    -   **運用上のポイント**:
        -   変更時は必ず本番適用前に stg 環境でテスト。

### infra/k8s/

-   **user-service/**

    -   **各ファイル責務**:
        -   deployment.yaml: user-service の Deployment 定義（replica 数, image, env, resource, secret 連携, liveness/readiness probe, affinity, tolerations 等）。
        -   service.yaml: ClusterIP/LoadBalancer 等の Service リソース（サービスディスカバリ/外部公開）。
        -   ingress.yaml: Ingress/ALB Ingress リソース（ALB 連携, HTTPS/TLS 終端, path routing）。
        -   hpa.yaml: HorizontalPodAutoscaler（CPU/メモリ/カスタムメトリクスで自動スケール）。
        -   pdb.yaml: PodDisruptionBudget（最小稼働数保証, ローリングアップデート時の可用性担保）。
        -   secret.yaml: DB 認証情報や API キー等の Secret（K8s Secret, AWS SecretsManager 連携）。
    -   **使い所**:
        -   サービス単位で独立運用・スケール・障害隔離。
    -   **運用上のポイント**:
        -   新サービス追加時は必ず同様の構成で分離管理。

-   **video-service/**, **chat-service/**

    -   user-service と同様に各マイクロサービスの K8s リソースを分離管理。

-   **istio/**

    -   **各ファイル責務**:
        -   gateway.yaml: Istio Gateway リソース（ALB からの入口、TLS 終端、複数ドメイン対応）。
        -   virtualservice.yaml: VirtualService（パス/ホストごとのルーティング、A/B テスト、カナリアリリース）。
        -   destinationrule.yaml: DestinationRule（mTLS, 負荷分散, CircuitBreaker, レートリミット, バージョン分離）。
        -   authorizationpolicy.yaml: AuthorizationPolicy（サービス間・外部からの認可、JWT claim/RBAC/ABAC）。
        -   requestauthentication.yaml: RequestAuthentication（JWT/OIDC 検証、外部 IdP 連携）。
    -   **使い所**:
        -   サービスメッシュのトラフィック制御・セキュリティ・認可の中核。
    -   **運用上のポイント**:
        -   ルーティングや認可変更時は必ず stg 環境でテスト。

-   **db/**

    -   rds-operator.yaml: RDS Operator 等の DB 運用自動化（フェイルオーバー、バックアップ、スケール）。
    -   secret.yaml: DB 接続情報（K8s Secret, AWS SecretsManager 連携）。

-   **monitoring/**
    -   prometheus.yaml: Prometheus の K8s マニフェスト（ServiceMonitor, Alertmanager 連携）。
    -   grafana.yaml: Grafana の K8s マニフェスト（ダッシュボード自動登録）。
    -   kiali.yaml: Kiali の K8s マニフェスト（サービスメッシュ可視化）。
    -   cloudwatch-agent.yaml: CloudWatch Agent マニフェスト（AWS 統合監視）。

### src/

-   **user-service/**
    -   main.go: Go のサービス本体（エントリーポイント、API ルーティング、認証認可・DB 連携）。
    -   Dockerfile: コンテナビルド用（multi-stage build, 最小権限ランタイム）。
    -   go.mod: Go 依存管理（バージョン固定、セキュリティ対応）。
    -   README.md: サービス仕様・API 仕様・起動方法・環境変数説明。
    -   tests/unit/: 単体テスト（go test, モック利用, カバレッジ測定）。
    -   tests/integration/: 統合テスト（DB 連携、外部 API 連携）。
    -   tests/e2e/: E2E/API テスト（API サーバー起動 →API テスト、Playwright/Postman 等）。
-   **video-service/**
    -   app.js: Node.js サービス本体（Express/Fastify, API ルーティング, S3 連携, 認証認可）。
    -   Dockerfile, package.json, README.md, tests/…: user-service と同様。
-   **chat-service/**
    -   main.py: Python サービス本体（FastAPI/Flask, WebSocket, 認証認可）。
    -   Dockerfile, requirements.txt, README.md, tests/…: user-service と同様。

### scripts/

-   **db-migrate.sh**
    -   DB マイグレーション自動化（各サービスのマイグレーションツール呼び出し、環境変数で DB 接続先切替）。
-   **deploy.sh**
    -   手動デプロイ補助（kubectl, helm, terraform 等のラッパー、環境切替対応）。
-   **cleanup.sh**
    -   リソース削除・クリーンアップ（開発環境のリセット、不要リソース一括削除）。

### .env.example

-   **責務**:
    全サービス共通・個別の環境変数テンプレート（DB/ECR/認証情報/外部 API キー等）。
    -   開発者が.env を作る際の唯一の参照元。

### README.md

-   **責務**:
    プロジェクト全体の概要・セットアップ手順・開発フロー・運用ルール・トラブル時の連絡先・拡張方針。

### Makefile

-   **責務**:
    標準化コマンド（build/test/lint/deploy/clean 等）。 - サービスごと・全体での一括操作や CI/CD からの呼び出しもここで統一。
    とても良いまとめ方ですが、**現場でさらに迷わないためには、もう一歩踏み込んだ「責務の具体化」「使い所」「運用上のポイント」「連携例」「拡張時の注意」**まで記述しておくと完璧です。

以下、**各サービス・基盤要素の責務・使い所・運用ポイント・連携例**を一切省略せずに詳細化します。

## 3. 各サービス・基盤要素の責務・使い所・運用ポイント

### user-service

-   **責務**

    -   ユーザー登録・認証（サインアップ/サインイン/パスワードリセット等）
    -   JWT 発行・検証（全 API の認証基盤）
    -   プロフィール管理 API（ユーザー情報の CRUD）
    -   他サービス（video-service, chat-service）からのユーザー情報参照 API（認可判定も含む）
    -   RBAC/ABAC の中心（ユーザー属性・権限管理）
    -   DB（RDS/Aurora）との連携（ユーザー情報永続化）

-   **使い所**

    -   すべての API リクエストは user-service で認証（JWT）を通す
    -   サービス間通信でも JWT を伝播し、user-service で検証
    -   他サービスが「このユーザーで正しいか？」を問い合わせる際の唯一の窓口

-   **運用ポイント**

    -   パスワードリセットや多要素認証（MFA）など、セキュリティ要件の拡張もここで吸収
    -   DB スキーマ変更時はマイグレーション・テスト・バックアップ必須

-   **連携例**
    -   video-service が動画アップロード時、user-service で「アップロード権限があるか」を JWT で検証
    -   chat-service がチャット送信時、user-service で「BAN されていないか」などを問い合わせ

### video-service

-   **責務**

    -   動画アップロード API（ファイル受信・S3 等ストレージ連携）
    -   動画メタデータ管理（DB にタイトル・説明・所有者・公開範囲などを保存）
    -   動画ストリーミング API（再生リクエスト →S3 署名付き URL 発行など）
    -   ユーザーごとの動画一覧・検索 API
    -   アクセス権限判定（user-service の認証情報/JWT を検証）

-   **使い所**

    -   ユーザー認証は必ず user-service の JWT で
    -   ストレージは S3 など外部サービスと連携
    -   動画の公開範囲や視聴権限は user-service の属性で判定

-   **運用ポイント**

    -   S3 バケットポリシーや署名付き URL の有効期限管理
    -   大容量ファイルのアップロード時は分割/リトライ/進捗管理も考慮

-   **連携例**
    -   user-service から「このユーザーは有料会員か？」を問い合わせて有料動画の視聴可否を判定

### chat-service

-   **責務**

    -   チャットルーム作成・参加・退出 API
    -   メッセージ送受信 API（REST/HTTP, WebSocket 両対応）
    -   メッセージ永続化（RDS/DynamoDB/ElastiCache 等と連携）
    -   メッセージ履歴取得・検索 API
    -   ユーザー認証（user-service の JWT 検証）

-   **使い所**

    -   WebSocket によるリアルタイム通信にも JWT 認証を必ず組み込む
    -   ルームごとの参加権限・発言権限も user-service で判定
    -   メッセージの保存先は用途・パフォーマンス要件で選択

-   **運用ポイント**

    -   スケールアウト時はセッション管理やメッセージ重複排除も設計
    -   スパム対策や BAN ユーザーの即時切断もここで吸収

-   **連携例**
    -   user-service から「このユーザーはこのルームに参加できるか？」を問い合わせて入室判定

### istio

-   **責務**

    -   サービスメッシュ基盤（全サービス間の通信をプロキシ経由で制御）
    -   mTLS 強制（全サービス間通信の暗号化と認証）
    -   トラフィック制御（A/B テスト、カナリア、リトライ、サーキットブレーカー、レートリミット）
    -   サービス間 RBAC/ABAC（AuthorizationPolicy/RequestAuthentication）
    -   可観測性（トレース・メトリクス・ログの自動収集）

-   **使い所**

    -   セキュリティ要件やネットワーク制御はすべて Istio で一元管理
    -   サービス追加時は必ずサイドカー注入・mTLS 有効化

-   **運用ポイント**
    -   Istio のバージョンアップは慎重に。Pilot/Ingress/Egress の可用性も監視
    -   トラフィック制御ルール変更時は影響範囲を必ずテスト

### OPA/Gatekeeper

-   **責務**

    -   K8s リソースの Admission コントロール（Rego ポリシーでガバナンス強制）
    -   例：全リソースにラベル必須、特権 Pod 禁止、イメージ署名必須、リソースリミット必須など

-   **使い所**

    -   開発者・運用者が不用意に危険なリソースを作成できないようにする
    -   監査証跡やガバナンス要件の実現

-   **運用ポイント**
    -   ポリシー追加・変更時は必ず stg 環境でテスト
    -   違反時の通知・自動修復も設計

### Prometheus/Grafana/Kiali/CloudWatch

-   **責務**

    -   Prometheus：K8s・アプリ・インフラのメトリクス収集
    -   Grafana：ダッシュボード可視化・アラート
    -   Kiali：Istio サービスメッシュの可視化・トラフィック分析
    -   CloudWatch：AWS リソースの監視・アラート・ログ集約

-   **使い所**

    -   サービスごと・クラスタごとに監視対象・アラートルールを設計
    -   障害発生時のトラブルシュート・根本原因分析

-   **運用ポイント**
    -   監視対象追加時は必ず Prometheus/Grafana/Kiali/CloudWatch の設定も更新
    -   アラートは Slack/Teams/メール等に自動通知

### Terraform

-   **責務**

    -   AWS リソース（VPC/EKS/ALB/RDS/ACM/IAM/S3/CloudWatch 等）の IaC 管理
    -   モジュール化による再利用性・環境差分管理

-   **使い所**

    -   クラウド基盤の再現性・変更履歴管理
    -   環境追加（dev/stg/prd）や構成変更時の唯一の変更点

-   **運用ポイント**
    -   terraform plan/apply は必ず PR レビュー後に実施
    -   State ファイルは S3+Lock で管理。State 破損時の復旧 Runbook も用意

### CI/CD

-   **責務**

    -   Lint/テスト/ビルド/セキュリティチェック/デプロイ自動化
    -   OPA/Gatekeeper によるポリシーチェックも自動化
    -   ECR へのイメージプッシュ、ArgoCD による GitOps デプロイ

-   **使い所**

    -   すべての変更は CI/CD を通じて品質・セキュリティを担保
    -   サービス追加時は CI/CD フローも必ず拡張

-   **運用ポイント**
    -   失敗時の対応フロー・ロールバック手順・通知ルールも明記
    -   セキュリティ脆弱性やポリシー違反は Fail で即時検知

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
            - name: Go Lint
              run: golangci-lint run ./...
              working-directory: src/user-service
            - name: Go Unit Test
              run: go test ./...
              working-directory: src/user-service
            - name: Node Lint
              run: npx eslint .
              working-directory: src/video-service
            - name: Node Unit Test
              run: npx jest
              working-directory: src/video-service
            - name: Python Lint
              run: flake8 .
              working-directory: src/chat-service
            - name: Python Unit Test
              run: pytest tests/unit/
              working-directory: src/chat-service
            - name: Build Docker image (Go)
              run: docker build -t user-service:latest .
              working-directory: src/user-service
            - name: Trivy Scan (Go)
              uses: aquasecurity/trivy-action@v0.11.2
              with:
                  image-ref: user-service:latest
            - name: Kube-linter
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
module "cloudwatch" { ... }
module "iam" { ... }
module "s3" { ... }
# 各種リソースのIaC管理
```

## 4. GitHub/CI/CD/クラウド側の設定

-   **GitHub Secrets**

    -   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
    -   `SNYK_TOKEN`
    -   `ARGOCD_SERVER`/`ARGOCD_USERNAME`/`ARGOCD_PASSWORD`

-   **ECR リポジトリ作成**

    ```
    aws ecr create-repository --repository-name user-service --region ap-northeast-1
    ```

-   **ArgoCD インストール＆アプリ登録**

    -   EKS 上に ArgoCD
    -   `argocd app create`で cicd/argocd-apps/の yaml を登録

-   **Snyk/Trivy/kube-linter/OPA は GitHub Actions で自動実行**

## 5. 補足・運用上の注意

-   **各サービスごとに src/・infra/k8s/・cicd/以下を分割管理**
-   **ドキュメントは必ず最新化し、運用 Runbook・障害対応・SLA/SLO も明記**
-   **DB は RDS/Aurora のマルチ AZ 冗長化＋ K8s シークレット連携**
-   **監視は Prometheus/Grafana/Loki/Kiali/CloudWatch 等を多層で組み合わせ**
-   **CI/CD はセキュリティ自動化・品質保証・自動デプロイまで一気通貫**

## 6. まとめ

-   **このディレクトリ構成・ファイル責務・CI/CD 設計をベースに、世界最高峰レベルのクラウドネイティブ開発・運用が可能**
-   **全ての工程で「なぜ必要か」「どこで管理するか」「どう自動化するか」を明確化**
-   **各種領域(DB 冗長化、認証認可、運用 Runbook、監視設計等)は個別に詳細設計として docs/以下に記述**
