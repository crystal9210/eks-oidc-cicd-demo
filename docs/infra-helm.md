# Helm チャート運用・設計・拡張 ドキュメント

このドキュメントは、EKS×Istio× マイクロサービス基盤の**Helm チャートによるミドルウェア/アプリの運用・設計・拡張・監査・障害対応**を、
**AWS 公式・CNCF・現場ベストプラクティスに基づき、一切省略せず**記述します。

## 1. ディレクトリ・チャート設計

### 1.1 ディレクトリ構成例

```
infra/helm/
  ├── istio/
  │    └── values.yaml
  ├── prometheus/
  │    └── values.yaml
  ├── grafana/
  │    └── values.yaml
  ├── gatekeeper/
  │    └── values.yaml
  └── Chart.yaml（必要に応じて独自チャート化）
```

-   **各ミドルウェア（Istio/Prometheus/Grafana/Gatekeeper 等）ごとにサブディレクトリ+values.yaml で分離管理**
-   **独自アプリや追加カスタムリソースは Chart.yaml/テンプレートディレクトリで独自チャート化**

### 1.2 チャートのバージョン管理・運用

-   **Helm リリースはバージョンタグで管理（例: istio-1.22.0, prometheus-56.0.0 等）**
-   **values.yaml の変更は必ず Git 管理＋ PR レビュー**
-   **Helm リポジトリ（公式/サードパーティ/自社）を明確に分離**

## 2. values.yaml 設計・管理

### 2.1 設計方針

-   **環境ごと（dev/stg/prod/cluster 単位）に values-.yaml を分離管理**
-   **Secret/認証情報は External Secrets 等で連携し、values.yaml には直接記載しない**
-   **リソース制限・アラート・監査設定も values.yaml で明示**

### 2.2 主要ミドルウェアの設定例

#### Istio

-   mTLS/PeerAuthentication/Ingress/EgressGateway/Telemetry/Tracing/SidecarInjection
-   Pilot/IngressGateway の HPA/PodDisruptionBudget/PodSecurityContext

#### Prometheus

-   ServiceMonitor/PodMonitor/Alertmanager 連携
-   Retention/Storage/Resource/Rule/Target 設定

#### Grafana

-   DataSource/ダッシュボード自動登録/ユーザー管理/Alert 設定

#### Gatekeeper

-   ConstraintTemplate/Constraint/ViolationAction/Sync/Logging

## 3. Helm 運用手順（正常系・異常系）

### 3.1 正常系：インストール・アップグレード

1. **リポジトリ追加/更新**
    ```sh
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update
    ```
2. **初回インストール**
    ```sh
    helm install istio-base istio/base -n istio-system
    helm install istiod istio/istiod -n istio-system -f istio/values.yaml
    ```
3. **アップグレード**
    ```sh
    helm upgrade istiod istio/istiod -n istio-system -f istio/values.yaml
    ```
4. **差分確認**
    ```sh
    helm diff upgrade istiod istio/istiod -n istio-system -f istio/values.yaml
    ```
5. **Rollback**
    ```sh
    helm rollback istiod  -n istio-system
    ```

### 3.2 異常系：障害・復旧手順

#### values.yaml 誤設定・デプロイ失敗

1. `helm history  -n `でリビジョン確認
2. `helm rollback   -n `
3. 失敗時は`kubectl describe pod`/`kubectl logs`で詳細調査
4. 必要なら`helm uninstall`→ 再 install

#### チャートバージョン不整合・依存エラー

1. 公式リリースノートを確認し、依存関係を明示的に指定
2. `helm dependency update`でチャート依存を同期
3. 互換性問題は stg 環境で必ず事前検証

#### リソース競合・削除事故

1. `helm list -A`で全リリース状態を確認
2. `helm uninstall  -n `で不要リリースを削除
3. ResourcePolicy: keep 設定で重要リソースの削除防止

## 4. CI/CD 連携・Chart Testing

-   **Chart Testing（ct）/Helm Lint を CI で自動実行**
    ```sh
    helm lint istio/
    ct install --charts istio/
    ```
-   **PR 時に values.yaml/Chart.yaml の差分を自動テスト**
-   **ArgoCD/Flux 等の GitOps ツールと連携し、Helm リリースを自動同期**
-   **Helm Secrets/External Secrets で Secret 値の Git 漏洩を防止**

## 5. セキュリティ・監査・コンプライアンス

-   **RBAC/PodSecurityContext/ResourceQuota/LimitRange 等は values.yaml で明示**
-   **Helm リリース/アップグレード/削除は監査証跡（kubectl/CloudTrail/ArgoCD Audit）で記録**
-   **Helm Chart の署名/検証（Helm v3+Cosign/Notary）も推奨**
-   **脆弱性のある Chart/イメージは CI/CD で Fail**

## 6. 拡張・運用時のチェックリスト

-   [ ] 新ミドルウェア追加時はサブディレクトリ＋ values.yaml ＋ Chart.yaml を追加
-   [ ] values.yaml/Chart.yaml 変更時は stg でテストし本番適用
-   [ ] Helm リリース/アップグレード/削除は必ず PR ＋監査証跡
-   [ ] Chart Testing/Helm Lint/CI/CD 連携は必ず維持
-   [ ] 公式/サードパーティ/自社チャートは明確に分離

## 7. 参考リンク・外部標準

-   [Helm 公式](https://helm.sh/)
-   [Chart Testing 公式](https://github.com/helm/chart-testing)
-   [ArgoCD 公式](https://argo-cd.readthedocs.io/)
-   [Kubernetes Helm Best Practices](https://docs.bitnami.com/tutorials/best-practices-for-securing-helm-charts/)

**このドキュメントは、現場最高水準の Helm 運用・拡張・監査・障害対応・CI/CD・セキュリティ・コンプライアンスまで一切迷わずに運用することを想定しています。**
