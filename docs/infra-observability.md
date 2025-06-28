# 可観測性（Observability）設計・運用・監査・障害対応 ドキュメント

このドキュメントは、EKS×Kubernetes×AWS 基盤の**可観測性（メトリクス・ログ・トレーシング・アラート・ダッシュボード・統合監視）設計・運用・監査・障害対応・拡張**を、
**AWS 公式・CNCF・PCI DSS/ISMS/法令・現場ベストプラクティス・運用制約まで一切省略せず**、
**設計思想・具体構成・手順・Runbook・CI/CD・監査証跡・障害復旧・拡張方針まで体系的に記述します。**

## 0. 可観測性の全体像・責任分界

-   **AWS 責任共有モデル**

    -   AWS は CloudWatch/CloudTrail/GuardDuty 等の基盤サービスを提供し、インフラの可観測性基盤を管理。
    -   ユーザーはアプリケーション、Kubernetes、ネットワーク、セキュリティ、監査の可観測性設計・運用・監査・アラート設定・復旧の全責任を負う。

-   **可観測性の 3 本柱**
    -   **メトリクス**：Prometheus、CloudWatch などでリソース使用率や SLO 監視
    -   **ログ**：Loki、CloudWatch Logs でアプリ・インフラ・監査ログ集約
    -   **トレーシング**：Jaeger、X-Ray で分散トレースと根本原因分析

## 1. 可観測性の要素・設計指針

### 1.1 メトリクス設計

-   **Prometheus Operator を利用し、Kubernetes クラスタ・Istio・アプリケーションのメトリクスを収集**
-   **AWS CloudWatch Container Insights を有効化し、EKS ノード・Pod・Windows ワークロードの詳細メトリクスを収集**
-   **メトリクスの命名規則は OpenMetrics 標準に準拠**
-   **SLO/SLA に基づくアラートルールを Prometheus Alertmanager で設定**
-   **メトリクスのラベル設計はアプリ名・環境・リージョン・バージョンを必ず含める**

#### 具体例：Prometheus アラートルール

```yaml
groups:
    - name: k8s.rules
      rules:
          - alert: HighPodRestart
            expr: increase(kube_pod_container_status_restarts_total[5m]) > 3
            for: 10m
            labels:
                severity: critical
            annotations:
                summary: "Pod {{ $labels.pod }} is restarting frequently"
                description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has restarted more than 3 times in 5 minutes."
```

### 1.2 ログ設計

-   **アプリケーションは JSON 形式で構造化ログを出力（例：logrus、zap、winston、structlog 等）**
-   **Kubernetes の Pod ログ、Node ログ、Istio Envoy アクセスログを Loki に集約**
-   **AWS CloudWatch Logs に ALB アクセスログ、CloudTrail、GuardDuty ログを集約**
-   **ログの保存期間は PCI DSS 等の規制に準拠し最低 1 年を推奨**
-   **ログのインデックス設計は検索性とコストバランスを考慮**

#### 具体例：Loki ログクエリ

```logql
{app="user-service", level="error"} |= "timeout"
```

### 1.3 トレーシング設計

-   **Istio の Envoy サイドカーで分散トレースを自動収集**
-   **Jaeger をトレーシングバックエンドとして導入し、OpenTelemetry SDK でアプリケーションからカスタムスパンを送信**
-   **トレース ID を全ログに埋め込み、ログ・メトリクス・トレースの相関分析を可能にする**
-   **パフォーマンスボトルネック・依存関係・エラー箇所の迅速特定に活用**

## 2. 統合監視・ダッシュボード設計

-   **Grafana をメトリクス・ログ・トレーシングの統合ダッシュボード基盤として利用**
-   **Kiali で Istio サービスメッシュのトポロジ・トラフィック・異常検知を可視化**
-   **SLO/SLA/SI を定義し、リアルタイムでダッシュボードに表示**
-   **経営層・運用・開発チームで共有可能なビューを作成**

## 3. アラート設計・自動通知・エスカレーション

### 3.1 Prometheus Alertmanager 設定例

-   **Slack/PagerDuty/JIRA 連携**
-   **ノイズ抑制（Silence）と自動エスカレーション設定**
-   **重要度別アラート分類（critical/warning/info）**

```yaml
receivers:
    - name: "slack-critical"
      slack_configs:
          - channel: "#alerts-critical"
            send_resolved: true
route:
    group_by: ["alertname"]
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 1h
    receiver: "slack-critical"
    routes:
        - match:
              severity: "warning"
          receiver: "slack-warning"
```

### 3.2 CloudWatch Alarms 例

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "HighCPUUsage" \
  --metric-name CPUUtilization \
  --namespace AWS/EKS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:region:account-id:alert-topic
```

## 4. 監査証跡・セキュリティ監視

-   **CloudTrail/Config/GuardDuty/SecurityHub で AWS 全リソースの操作・脅威を監査**
-   **Kubernetes Audit Policy で API サーバー操作を CloudWatch Logs/SIEM に転送**
-   **Falco を導入し、Pod/ノードのランタイム異常（不審なシステムコール等）をリアルタイム検知**
-   **監査証跡は PCI DSS・ISMS に準拠した保存期間・検索性を確保**

## 5. 障害対応・復旧 Runbook

### 5.1 正常系運用フロー

1. 毎朝 Grafana ダッシュボード・アラート履歴を確認
2. バッチ・ジョブ・Pod の正常稼働を確認
3. 監査証跡ログを定期レビュー

### 5.2 異常系対応例

-   **Pod 障害・OOM・CrashLoopBackOff**
    -   アラート受信 →`kubectl logs`・`kubectl describe`で原因調査 → 再起動/再デプロイ → 監査ログ記録
-   **ネットワーク断・外部 API 障害**
    -   Kiali/トレースで断点特定 →SG/ALB/Route53/NetworkPolicy 確認 → 復旧 → 再監視
-   **セキュリティ異常**
    -   GuardDuty/Falco 検知 → 影響範囲分析 → 隔離・Secret ローテーション → 復旧・証跡記録

## 6. CI/CD 連携・拡張

-   **Prometheus ルール・Grafana ダッシュボード・Alertmanager 設定は Git 管理し PR レビュー必須**
-   **kube-linter・OPA Gatekeeper で監視設定の静的解析を CI で自動化**
-   **ArgoCD/Flux で監視リソースを GitOps 運用**
-   **監査証跡・ログ収集設定も IaC で管理**

## 7. 具体的なコマンド例

```bash
# Prometheusメトリクス確認
kubectl port-forward svc/prometheus-operated 9090
curl http://localhost:9090/api/v1/query?query=kube_pod_status_phase

# Lokiログクエリ
kubectl port-forward svc/loki 3100
curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={app="user-service"} |= "error"'

# Jaegerトレースアクセス
kubectl port-forward svc/jaeger-query 16686

# Alertmanager通知確認
kubectl port-forward svc/alertmanager-operated 9093
```

## 8. ベストプラクティス・チェックリスト

-   [ ] メトリクス・ログ・トレースは必ず構造化・ラベル付けを統一
-   [ ] 監査証跡は PCI DSS/ISMS 準拠で最低 1 年保存
-   [ ] アラートは重大度別に分類しノイズを抑制
-   [ ] ダッシュボードは経営・運用・開発で共有
-   [ ] 障害対応 Runbook は必ず作成・定期訓練
-   [ ] CI/CD で監視設定の静的解析・自動テストを必須化

## 9. 参考リンク

-   [AWS Observability Blog（最新情報）](https://aws.amazon.com/jp/blogs/news/tag/observability/) [1]
-   [AWS Observability Services（2025 年最新資料）](https://pages.awscloud.com/rs/112-TZM-766/images/AWS_Summit_2025_A-08A_20250625_CloudOps_O11y_AWS_Observability_Services.pdf) [2]
-   [AWS EKS Reliability Best Practices](https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/reliability.html) [6]
-   [Falco Amazon EKS Add-On](https://sysdig.jp/blog/falco-amazon-eks-add-on/) [8]
-   [Prometheus Operator GitHub](https://github.com/prometheus-operator/prometheus-operator)

**このドキュメントは、現場で即使える詳細な設計・運用・監査・障害対応・CI/CD 連携・具体例・コマンド例・Runbook まで網羅しています。**

[1] https://aws.amazon.com/jp/blogs/news/tag/observability/

[2] https://pages.awscloud.com/rs/112-TZM-766/images/AWS_Summit_2025_A-08A_20250625_CloudOps_O11y_AWS_Observability_Services.pdf

[3] https://www.softbank.jp/biz/blog/cloud-technology/articles/202506/weekly-aws-0602/

[4] https://aws.amazon.com/jp/blogs/news/aws-reinforce-roundup-2025-top-announcements/

[5] https://www.infoq.com/jp/news/2025/01/aws-container-insights-ecs/

[6] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/reliability.html

[7] https://dev.classmethod.jp/articles/aws-summary-2025/

[8] https://sysdig.jp/blog/falco-amazon-eks-add-on/
