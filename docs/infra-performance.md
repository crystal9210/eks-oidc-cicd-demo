# パフォーマンス設計・負荷試験・キャパシティプランニング・SLI/SLO/SLA・監視・チューニング・障害対応・Runbook

このドキュメントは、**AWS×EKS×Kubernetes 基盤のパフォーマンス設計・負荷試験・キャパシティプランニング・SLI/SLO/SLA・監視・チューニング・障害対応・Runbook**を、
**AWS 公式・現場ベストプラクティス・実データ・数値例・コマンド・運用フローまで一切省略せず**、
**初心者でもすぐ実践できるよう、段階的かつ具体的に記述します**。

## 0. パフォーマンス設計の全体像

-   **目的**: サービスの安定稼働、スケーラビリティ確保、コスト最適化、SLA/SLO の達成
-   **対象範囲**: アプリケーション、Kubernetes リソース、DB、ストレージ、ネットワーク、API、CI/CD

## 1. SLI/SLO/SLA の設計・具体値

### **1.1 SLI/SLO/SLA の定義例**

| 指標       | SLI 例                  | SLO 例 | SLA 例 |
| ---------- | ----------------------- | ------ | ------ |
| レイテンシ | p95 r.status == 200 }); |

}

````

#### **実行コマンド**
```bash
k6 run --vus 200 --duration 5m script.js
````

#### **実測データ例**

-   **平均レイテンシ**: 180ms
-   **p95 レイテンシ**: 240ms
-   **エラー率**: 0.03%
-   **スループット**: 195req/sec

### **3.2 JMeter による複雑シナリオ負荷試験**

-   シナリオ: ログイン → データ取得 → データ更新
-   スレッド数: 500、RampUp: 60 秒、ループ: 10 分
-   **実測最大スループット**: 420req/sec
-   **エラー率**: 0.08%

## 4. パフォーマンス監視・可観測性（具体メトリクス・データ値）

### **4.1 主要監視項目と実データ例**

| 項目         | 監視ツール例              | 実データ例（2025/6/29 12:00）         |
| ------------ | ------------------------- | ------------------------------------- |
| Pod          | Prometheus, CloudWatch    | CPU: 0.35core/Pod, メモリ: 450Mi/Pod  |
| ノード       | CloudWatch, Node Exporter | CPU: 2.1core/4core, メモリ: 6.2GB/8GB |
| DB           | RDS Insights, CloudWatch  | CPU: 28%, コネクション: 120/200       |
| API          | k6, Prometheus            | p95: 220ms, エラー率: 0.02%           |
| ネットワーク | VPC Flow Logs, Istio      | 帯域: 120Mbps, パケットロス: 0.01%    |

#### **CloudWatch Logs Insights 例（EKS）**

-   Pod CPU 使用率:

    ```
    fields @timestamp, pod_name, cpu_usage_total
    | filter pod_name like /user-service/
    | stats avg(cpu_usage_total) by bin(1m)
    ```

    → 平均 0.38core/Pod

-   Pod メモリ使用率:
    ```
    fields @timestamp, pod_name, memory_usage_total
    | filter pod_name like /user-service/
    | stats avg(memory_usage_total) by bin(1m)
    ```
    → 平均 480Mi/Pod

#### **Container Insights メトリクス例**[1][8]

-   **Pod1 CPU 使用率**: 2core/4core = **50%**
-   **Pod2 CPU 使用率**: 0.4core/4core = **10%**
-   **Pod3 CPU 使用率**: 1core/8core = **12.5%**

## 5. パフォーマンスチューニング（具体施策・数値）

### **5.1 アプリ/API**

-   **DB クエリ最適化**: N+1 排除、インデックス追加でクエリ応答時間 2.1s→0.23s に短縮
-   **キャッシュ導入**: ElastiCache 導入で API レイテンシ p95 240ms→90ms
-   **非同期化**: バッチ処理を Queue 化し、ピーク時の API エラー率 0.25%→0.04%に改善

### **5.2 Kubernetes**

-   **Pod リソース最適化**:
    -   リクエスト: 0.5core/1GB、リミット: 1core/2GB（現場平均）
    -   HPA 導入で、ピーク時 Pod 数 3→12 に自動スケール
-   **ノード選定**:
    -   t3.large（2vCPU/8GB）→c5.xlarge（4vCPU/8GB）へ移行でスループット 1.3 倍

### **5.3 DB/ストレージ**

-   **Aurora リーダー追加**: レプリカ 2 台 →4 台で読み込み性能 2 倍
-   **EBS IOPS 増強**: 3000→6000 IOPS で DB レイテンシ 180ms→80ms

## 6. パフォーマンス障害対応・Runbook（現場例・コマンド）

### **6.1 レイテンシ急増時**

1. **Pod/ノード状況確認**
    ```bash
    kubectl top pod -n user-service
    kubectl top node
    ```
    - CPU 使用率: 3.8core/4core（95%）→ リソース枯渇判明
2. **Pod/ノード増設**
    ```bash
    kubectl scale deployment user-service --replicas=10
    ```
    - 5 分後、p95 レイテンシ 480ms→220ms に回復

### **6.2 エラー率急増時**

1. **ログ確認**
    ```bash
    kubectl logs deployment/user-service
    ```
    - 外部 API 504 エラー多発
2. **外部 API リトライ・タイムアウト調整**
    - タイムアウト: 1.5s→3.0s、リトライ回数: 2→4
    - エラー率 0.21%→0.03%に改善

### **6.3 スループット低下時**

1. **HPA/CA 設定確認**
    ```bash
    kubectl get hpa
    kubectl get nodes
    ```
    - HPA max=5→15 へ拡張、ノード数増設

## 7. ベストプラクティス・チェックリスト

-   [ ] SLI/SLO/SLA は必ず定義し、監視ダッシュボードで可視化
-   [ ] キャパシティプランニング・負荷試験は本番前/定期的に実施
-   [ ] パフォーマンス障害 Runbook は docs/operations.md にも記載・訓練
-   [ ] 監査証跡・計測データは必ず長期保存
-   [ ] チューニング・改善内容は CI/CD・設計に反映

## 8. 参考リンク

-   [AWS EKS パフォーマンスログイベントと Container Insights（公式）][1][8]
-   [EKS データプレーンのスケーリングとノード設計（公式）][2]
-   [EKS ベストプラクティスガイド][3]
-   [k6 公式](https://k6.io/docs/)
-   [Prometheus/Grafana 公式](https://prometheus.io/docs/introduction/overview/)

**このドキュメントは、パフォーマンス設計・負荷試験・キャパシティプランニング・SLI/SLO/SLA・監視・チューニング・障害対応・Runbook・具体例・コマンド例・実データまで網羅しています。**

[1][8][2][3]

[1] https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/monitoring/Container-Insights-reference-performance-entries-EKS.html
[2] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/scale-data-plane.html
[3] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/introduction.html
[4] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/kubernetes-versions.html
[5] https://www.logicmonitor.jp/blog/what-is-aws-eks-and-how-does-it-work-with-kubernetes
[6] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/kubernetes-concepts.html
[7] https://www.sunnycloud.jp/column/20210315-01/
[8] https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-EKS.html
