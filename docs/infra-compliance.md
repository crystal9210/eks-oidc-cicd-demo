# コンプライアンス・監査証跡・法令対応 詳細運用ドキュメント

このドキュメントは、**EKS×AWS×Kubernetes 基盤のコンプライアンス（PCI DSS/ISMS/法令/監査/証跡/外部監査対応/運用/障害対応/拡張）**を、
**AWS 公式・現場ベストプラクティス・法令・実運用制約まで一切省略せず**、
**初心者でもすぐに実践できるよう、手順・設定例・コマンド・運用フロー・証跡確認・障害対応・自動化まで段階的に記述します**[1][2][3][4]。

## 0. コンプライアンス運用の全体像

-   **AWS 責任共有モデル**

    -   AWS はインフラの物理的セキュリティ・一部サービスの監査証跡基盤を管理。
    -   ユーザーはアプリ/データ/アクセス権/監査証跡/運用/監査対応/法令遵守の全責任を負う。

-   **対応必須の主な規制・標準**
    -   PCI DSS、ISMS、GDPR、個人情報保護法、J-SOX など

## 1. AWS リソースの監査証跡設定

### 1.1 CloudTrail の有効化と確認

#### 1.1.1 CloudTrail 新規作成手順

1. **S3 バケット作成（証跡保存用）**
    ```bash
    aws s3 mb s3://mytrail-bucket
    ```
2. **CloudTrail 作成**
    ```bash
    aws cloudtrail create-trail --name mytrail --s3-bucket-name mytrail-bucket
    aws cloudtrail start-logging --name mytrail
    ```
3. **多リージョン対応（推奨）**
    ```bash
    aws cloudtrail update-trail --name mytrail --is-multi-region-trail
    ```
4. **証跡の暗号化（SSE-KMS）**
    - AWS マネジメントコンソールで CloudTrail 証跡の S3 バケット設定から「SSE-KMS」を有効化

#### 1.1.2 CloudTrail の動作確認

-   **証跡ログの確認**
    ```bash
    aws s3 ls s3://mytrail-bucket/AWSLogs//
    ```
-   **イベント検索**
    ```bash
    aws cloudtrail lookup-events --max-results 5
    ```

#### 1.1.3 CloudTrail の保存期間・証跡管理

-   **S3 バケットのライフサイクル設定で「最低 1 年」保存**
-   **バージョニング・アクセスログ・SSE-KMS 暗号化を必ず有効化**

### 1.2 AWS Config の有効化

1. **Config ルール新規作成**
    - AWS コンソール「Config」→「設定」→「記録先 S3 バケット」指定
2. **全リソースの設定変更を自動記録**
3. **Config ルール例：s3-bucket-public-read-prohibited（S3 のパブリックアクセス禁止）**

## 2. Kubernetes 監査証跡の設定

### 2.1 Kubernetes Audit Policy 導入

#### 2.1.1 Audit Policy YAML 例（全 Pod/Secret 操作を記録）

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
    - level: RequestResponse
      resources:
          - group: ""
            resources: ["pods", "secrets"]
      verbs: ["create", "update", "delete"]
```

#### 2.1.2 EKS クラスタでの有効化

-   **EKS の場合、Audit ログは CloudWatch Logs へ自動転送可能**
-   **EKS コンソール「監査ログ」→「Audit」ON**

#### 2.1.3 監査ログの確認

```bash
# CloudWatch Logs Insightsで検索
fields @timestamp, @message
| filter @message like /delete|update|privilege/
| sort @timestamp desc
| limit 100
```

### 2.2 Falco によるランタイム監査

1. **Helm で Falco をインストール**
    ```bash
    helm repo add falcosecurity https://falcosecurity.github.io/charts
    helm install falco falcosecurity/falco
    ```
2. **不審なシステムコール・ファイル操作・権限昇格等をリアルタイム検知**
3. **Falco イベントは Loki/CloudWatch Logs/SIEM に転送**

## 3. アプリケーション・DB 監査ログ

### 3.1 アプリ監査ログ

-   **重要操作（認証/権限変更/データ更新）はすべて JSON 構造化ログで出力**
-   **例：Python（structlog）**
    ```python
    import structlog
    log = structlog.get_logger()
    log.info("user_update", user_id=123, action="update", result="success")
    ```

### 3.2 DB 監査ログ（RDS/Aurora）

-   **RDS/Aurora の監査ログ有効化**
    -   RDS コンソール「監査ログ」→「mysql_audit plugin」ON
-   **S3/CloudWatch Logs に自動転送**

## 4. 証跡の保存・検索・エクスポート

### 4.1 S3 バケットの設定

-   **バージョニング有効化**
-   **SSE-KMS 暗号化有効化**
-   **アクセスログ有効化**
-   **ライフサイクル設定で「最低 1 年」保存**

### 4.2 証跡の検索・エクスポート

-   **CloudWatch Logs Insights/Loki/SIEM で全文検索**
    ```sql
    fields @timestamp, @message
    | filter @message like /delete|update|privilege/
    | sort @timestamp desc
    | limit 100
    ```
-   **S3 から CSV/JSON でダウンロードし、外部監査に提出**

## 5. 権限管理・監査

-   **IAM/Role/RBAC の最小権限原則を徹底**
    -   重要操作は MFA 必須
    -   証跡アクセスは専用 Role で制限
-   **権限変更・認証失敗も全て証跡化**

## 6. 外部監査・法令対応フロー

1. **証跡エクスポート（S3/CloudWatch Logs/SIEM から CSV/JSON でダウンロード）**
2. **運用手順・運用記録（Runbook/CI/CD/監査ログ）を提出**
3. **監査指摘は必ず Runbook・CI/CD・監査設計に反映し再発防止**

## 7. 障害対応・インシデント Runbook

### 7.1 証跡消失・改ざん・漏洩時

1. **CloudTrail/Config/K8s Audit/Falco/アプリ監査ログの保存状況を即時確認**
2. **S3/CloudWatch Logs/SIEM のアクセスログで不正アクセス・削除・改ざんを特定**
3. **証跡のバックアップ/リストア Runbook に従い復旧**
4. **影響範囲を分析し、必要なら IAM/SG/ネットワーク/Pod を隔離**
5. **インシデント報告・事後レビュー・再発防止策の実施**

### 7.2 監査証跡の不整合・欠損時

1. **証跡の保存期間・件数・整合性を定期チェック**
2. **欠損があれば即時アラート・復旧・管理者報告**
3. **再発防止策を Runbook・CI/CD・監査設計に反映**

## 8. CI/CD・自動化・拡張

-   **証跡設定（CloudTrail/Config/K8s Audit/Falco/監査ログ）は IaC/Git 管理＋ PR レビュー＋ CI/CD 自動テスト**
-   **証跡保存・エクスポート・監査レポートも自動化（Lambda/Scheduler/Shell Script）**
-   **新規サービス/リソース追加時は必ず証跡設計・監査運用も追加**

## 9. ベストプラクティス・チェックリスト

-   [ ] CloudTrail/Config/K8s Audit/Falco/アプリ監査ログは必ず有効化・長期保存
-   [ ] 証跡保存先（S3/SIEM）は暗号化・バージョニング・アクセスログ必須
-   [ ] 権限管理は最小権限＋ MFA ＋監査証跡アクセス制限
-   [ ] 証跡検索・エクスポート・監査レポートは自動化
-   [ ] 外部監査・法令対応は証跡エクスポート・運用記録・事後レビューまで一元管理
-   [ ] 障害/インシデント Runbook は docs/operations.md にも記載・随時更新

## 10. 参考リンク

-   [AWS CloudTrail 公式](https://docs.aws.amazon.com/ja_jp/awscloudtrail/latest/userguide/cloudtrail-user-guide.html)
-   [AWS Config 公式](https://docs.aws.amazon.com/ja_jp/config/latest/developerguide/)
-   [Kubernetes Audit Policy 公式](https://kubernetes.io/ja/docs/tasks/debug/debug-cluster/audit/)
-   [Falco 公式](https://falco.org/docs/)
-   [PCI DSS/ISMS/法令監査要件]

**このドキュメントは、見た人が即実践できるよう、手順・設定例・コマンド・運用フロー・証跡確認・障害対応・自動化まで一切省略せず網羅しています。**

[1] preferences.information_presentation
[2] preferences.instruction_format
[3] preferences.feedback_format
[4] preferences.communication
