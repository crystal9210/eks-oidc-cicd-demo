# コスト管理・最適化・監査・自動化・運用 詳細ドキュメント＆手順書

このドキュメントは、**AWS×EKS×Kubernetes 基盤のコスト管理・最適化・監査・アラート・自動化・運用・障害対応**を、
**初心者でもすぐ実践できるよう、段階的な指示・具体的な数値例・コマンド・運用フロー・サンプルデータを交えて**記述します[1][2][3]。

## 0. コスト管理の全体像

-   **目的**: コストの見える化、無駄な支出の抑制、予算超過の防止、経営/運用/開発への配賦責任
-   **主な対象**: EKS クラスタ、EC2、S3、RDS、EBS、ALB、Lambda、K8s リソース（Namespace/Pod/Deployment 単位）

## 1. AWS コスト可視化・分析手順

### 1.1 Cost Explorer の使い方（サンプルデータ付き）

#### ステップ 1: 有効化

-   AWS マネジメントコンソール > Cost Explorer > [Cost Explorer の有効化]をクリック

#### ステップ 2: サービス別コスト分析

-   例：2025 年 6 月のサービス別コスト
    | サービス | コスト (USD) |
    |------------|--------------|
    | EC2 | $1,200 |
    | EKS | $350 |
    | S3 | $180 |
    | RDS | $400 |
    | Lambda | $25 |
    | 合計 | $2,155 |

#### ステップ 3: タグ別コスト配賦

-   タグ例：`Project=video`, `Environment=prod`
-   「フィルター」→「タグ」→`Project=video`でフィルタ
-   例：`Project=video`の 2025 年 6 月コスト = **$800**

#### ステップ 4: 期間別推移グラフ

-   2025 年 1 月～ 6 月の月次コスト推移例
    | 月 | コスト (USD) |
    |------|--------------|
    | 1 月 | $1,800 |
    | 2 月 | $1,950 |
    | 3 月 | $2,100 |
    | 4 月 | $2,000 |
    | 5 月 | $2,100 |
    | 6 月 | $2,155 |

#### ステップ 5: CSV エクスポート

-   [エクスポート]ボタン →CSV ダウンロード →Excel/Google Sheets で分析

### 1.2 Cost and Usage Report (CUR) の設定と Athena 分析

#### ステップ 1: S3 バケット作成

```bash
aws s3 mb s3://cost-report-bucket-202506
```

#### ステップ 2: CUR レポート作成

-   請求ダッシュボード > Cost and Usage Reports > [レポート作成]
-   S3 バケットに保存先指定、日次/CSV 形式推奨

#### ステップ 3: Athena で分析

-   Athena テーブル作成（ウィザード利用で OK）
-   サンプルクエリ：2025 年 6 月の EKS コスト合計
    ```sql
    SELECT line_item_product_code, SUM(line_item_unblended_cost) AS cost
    FROM cost_usage_report
    WHERE usage_start_date BETWEEN date '2025-06-01' AND date '2025-06-30'
      AND line_item_product_code = 'AmazonEKS'
    GROUP BY line_item_product_code;
    ```
-   結果例：`AmazonEKS`, `$350.00`

### 1.3 Kubecost による K8s コスト配賦

#### ステップ 1: インストール

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer --namespace kubecost --create-namespace
```

#### ステップ 2: ダッシュボードアクセス

-   `kubectl port-forward svc/kubecost-cost-analyzer 9090:9090 -n kubecost`
-   ブラウザで http://localhost:9090 へアクセス

#### ステップ 3: サンプルコストデータ

| Namespace     | コスト (USD/6 月) |
| ------------- | ----------------- |
| user-service  | $120              |
| video-service | $95               |
| chat-service  | $65               |
| monitoring    | $30               |

#### ステップ 4: Pod/Deployment 単位のコスト分析

-   「Cost Allocation」→Pod/Deployment 別にリスト表示
-   例：`user-service-deployment` の 6 月コスト = **$80**

## 2. 予算設定・アラート・自動通知

### 2.1 AWS Budgets で予算アラート

#### ステップ 1: 新規予算作成

-   請求ダッシュボード > Budgets > [予算作成]
-   例：月額予算 = **$2,000**

#### ステップ 2: アラート閾値設定

-   例：80%（$1,600）、100%（$2,000）でアラート
-   通知先：メール、Slack（SNS 連携）、Webhook

#### ステップ 3: アラート受信例

-   6 月 20 日時点でコストが$1,650 → 「80%超過」アラートメールが届く

### 2.2 Cost Anomaly Detection の設定

#### ステップ 1: 異常検知ジョブ作成

-   Cost Management > Cost Anomaly Detection > [ジョブ作成]
-   例：EKS コストが 1 日で$50 以上増加した場合に通知

#### ステップ 2: 通知例

-   6 月 15 日、EKS コストが$30→$90 に急増 → 「異常検知」メール/SNS 通知

## 3. コスト最適化・自動化

### 3.1 Savings Plans/RI の具体値例

-   **オンデマンド（t3.medium, 1 台, 1 ヶ月）**: 約$30
-   **1 年 RI（t3.medium, 1 台, 1 ヶ月）**: 約$19（36%割引）
-   **Savings Plans（全体）**: 最大 72%割引

### 3.2 Compute Optimizer の使い方

#### ステップ 1: 有効化

-   AWS コンソール > Compute Optimizer > [有効化]

#### ステップ 2: 推奨例

-   `m5.large`（現状コスト：$70/月）→ `t3.medium`（推奨コスト：$30/月）
    → 年間で$480 コスト削減

### 3.3 オートスケーリング・スケジューリング例

-   **EKS ノードグループ**
    -   最小 2 台、最大 10 台、CPU70%超で自動増減
-   **Lambda/バッチ**
    -   EventBridge で夜間（22:00-8:00）は自動停止

## 4. コスト監査・証跡・法令対応

### 4.1 Cost and Usage Report を S3/Athena で長期保存

-   S3 バケット例：`cost-report-bucket-202506`
-   保存期間：最低 1 年（法令要件に応じて 7 年も可）

### 4.2 CloudTrail/Config でコスト関連操作の証跡化

-   例：EC2 インスタンス作成/削除、EBS ボリューム拡張、RI 購入などの操作履歴を全て記録

## 5. 障害対応・Runbook

### 5.1 予算超過・異常検知時の即時対応手順

1. **アラート受信（例：6 月 25 日、$2,100 で 100%超過）**
2. **Cost Explorer で「今月の急増サービス」を確認**
    - 例：ALB が$200→$400 に急増
3. **Kubecost で「どの Namespace/Pod が急増したか」分析**
    - 例：`video-service`の Pod 増加が原因
4. **不要リソース停止コマンド例**
    ```bash
    # 未使用EBS
    aws ec2 describe-volumes --filters Name=status,Values=available
    aws ec2 delete-volume --volume-id vol-xxxxxxxx
    # 未使用EIP
    aws ec2 describe-addresses --query "Addresses[?AssociationId==null]"
    aws ec2 release-address --allocation-id eipalloc-xxxxxxxx
    ```
5. **Savings Plans/RI/Auto Scaling 設定を見直し**
6. **事後レビュー・Runbook/CI/CD に反映**

## 6. ベストプラクティス・チェックリスト

-   [ ] Cost Explorer/CUR/Kubecost でコスト可視化・配賦を徹底
-   [ ] 予算・アラート・異常検知は必ず自動化
-   [ ] コスト最適化（RI/Savings/Auto Scaling/スケジューリング）を定期実施
-   [ ] コスト証跡・運用記録は監査・法令対応のため長期保存
-   [ ] コスト急増・予算超過時は即時対応 Runbook を整備
-   [ ] コスト管理・最適化設定は IaC/Git 管理＋ PR レビュー＋ CI/CD 自動テスト

## 7. 参考リンク

-   [AWS Cost Explorer 公式](https://docs.aws.amazon.com/ja_jp/cost-management/latest/userguide/ce-what-is.html)
-   [AWS Budgets 公式](https://docs.aws.amazon.com/ja_jp/cost-management/latest/userguide/budgets-managing-costs.html)
-   [Kubecost 公式](https://kubecost.com/)
-   [AWS Compute Optimizer 公式](https://docs.aws.amazon.com/ja_jp/compute-optimizer/latest/ug/what-is.html)

**このドキュメントは、コスト管理・最適化・監査・自動化・運用・障害対応・ベストプラクティス・Runbook・具体例・コマンド例・数値サンプルまで一切省略せず網羅しています。**

[1] preferences.instruction_format
[2] programming.documentation
[3] projects.requirement_management
