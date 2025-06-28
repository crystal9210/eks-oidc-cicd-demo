# インシデント管理・障害対応・CSIRT・復旧・監査・事後レビュー ドキュメント＆Runbook 集

このドキュメントは、**AWS×EKS×Kubernetes 基盤のインシデント/障害/セキュリティ/運用/外部連携/コスト/自動化/バージョン管理/マルチクラスタ/ハイブリッド/サービスメッシュ/監査証跡**まで、
**現場最高水準・粒度・網羅性・運用/拡張/障害対応/監査/ベストプラクティス/公式制約/具体例/コマンド例/Runbook**を一切省略せず体系化しています[1][2]。

## 0. インシデント管理の全体像・基本方針

-   **目的**
    -   サービス停止・データ損失・セキュリティ事故等の重大障害に対し、迅速な検知・通報・復旧・再発防止を実現
-   **適用範囲**
    -   システム障害、サービス停止、データ破損・消失、セキュリティインシデント（不正アクセス/情報漏洩/DDoS 等）、法令違反、外部通報、コスト急増、バージョン不整合、外部 API 障害

## 1. インシデント/障害カテゴリ一覧と網羅例

| カテゴリ              | 代表的な障害例・インシデント例                                  |
| --------------------- | --------------------------------------------------------------- |
| クラスタ全体          | コントロールプレーン不可、証明書失効、バージョン不整合          |
| ノード/Auto Scaling   | EC2 障害、ASG スケール失敗、カーネルパニック                    |
| Pod/ワークロード      | CrashLoopBackOff、OOM、Eviction、スケジューリング失敗           |
| ネットワーク          | VPC/SG/ENI/Pod SG/TransitGW/DirectConnect/Route 断              |
| ストレージ            | EBS/EFS/S3/PV/PVC バインド失敗、IOPS 枯渇、スナップショット復旧 |
| DB/NoSQL/Cache/Vector | RDS/Aurora/DocumentDB/DynamoDB/Neptune/ElastiCache/時系列/台帳  |
| CI/CD                 | デプロイ失敗、ArgoCD 同期失敗、イメージ Pull 失敗               |
| 監査・証跡            | CloudTrail/Config/K8s Audit/Falco/監査ログ消失・改ざん          |
| セキュリティ          | 侵入/権限昇格/脆弱性悪用/証明書漏洩/シークレット流出            |
| サービスメッシュ      | Istio/Linkerd/Envoy/トラフィック不整合/mTLS 障害                |
| 外部連携              | API Gateway/外部 API/サードパーティ障害                         |
| 自動化・バッチ        | Lambda/EventBridge/バッチ/定期ジョブ失敗                        |
| コスト/リソース枯渇   | Quota 超過/コスト急増/リソース上限/Spot 枯渇                    |
| バージョン管理・拡張  | EKS アップグレード失敗、Add-ons 障害、マルチクラスタ障害        |

## 2. インシデント検知・初動対応（全カテゴリ共通）

### **検知手段**

-   CloudWatch/Prometheus/Alertmanager/GuardDuty/Falco/SIEM アラート
-   ユーザー通報（サポート/Slack/電話）
-   定期ダッシュボード/監査証跡/運用点検

### **初動フロー**

1. **一次切り分け**
    - 例：CloudWatch アラートで EKS ノード障害検知
2. **影響範囲特定**
    - どのサービス/DB/ユーザー/外部連携が影響か
3. **CSIRT/運用当番へ即時通報**
    - Slack/PagerDuty/電話/メール
4. **インシデント管理システムに記録**
    - JIRA/Ticket/専用シート

## 3. 主要インシデントごとの Runbook・具体手順

### **3.1 クラスタ全体障害（例：コントロールプレーン不可）**

-   `eksctl get cluster` / `kubectl cluster-info` で状態確認
-   CloudTrail/eksctl/eks イベントで障害原因特定
-   バージョン不整合/証明書失効時は手動ロールバック/証明書再発行
-   サポートケース即時起票（AWS サポート/プレミアムサポート）
-   復旧後、監査証跡・再発防止策を記録

### **3.2 ノード障害/ASG スケール失敗**

```bash
kubectl get nodes
kubectl describe node
kubectl drain  --ignore-daemonsets
kubectl delete node
# ASGで新ノード自動追加
```

-   EC2 障害時は`aws ec2 describe-instances`で状態確認、必要なら再起動

### **3.3 Pod/ワークロード障害（CrashLoopBackOff/OOM）**

```bash
kubectl get pods -A
kubectl describe pod
kubectl logs
# OOMの場合はリソースリクエスト/リミット/ノードメモリ確認
# CrashLoopBackOffはイメージ/環境変数/依存サービス疎通確認
```

-   再発防止はリソース設計・HPA・PodDisruptionBudget 見直し

### **3.4 ネットワーク障害**

-   VPC/SG/NetworkPolicy/ENI/Pod SG/Route/TransitGateway 設定を確認
-   `kubectl exec`で Pod 間疎通テスト、Kiali でトポロジ確認
-   必要に応じて SG/Policy 修正・Pod 再起動

### **3.5 ストレージ障害（EBS/EFS/S3/PV/PVC）**

-   `kubectl describe pvc ` でバインド状況確認
-   EBS/EFS/S3 の状態は AWS CLI/コンソールで確認
-   スナップショット/バックアップからリストア
-   永続化設定/StorageClass/Pod 再スケジューリング

### **3.6 DB/NoSQL/Cache/ベクター DB 障害**

-   RDS/Aurora/DynamoDB/DocumentDB/ElastiCache/Neptune/Timestream/Bedrock Vector Engine
-   `aws rds describe-db-instances` / `aws dynamodb describe-table` で状態確認
-   フェイルオーバー/リストア/スナップショット復旧
-   DB 接続先切替/アプリ疎通テスト

### **3.7 CI/CD 障害**

-   GitHub Actions/ArgoCD/Manifest/イメージ Pull/パイプラインログ確認
-   必要なら手動再実行、Manifest/Secret/イメージタグ修正

### **3.8 監査・証跡障害**

-   CloudTrail/Config/K8s Audit/Falco/監査ログ消失・改ざん時は S3/バックアップからリストア
-   証跡の整合性・保存期間確認、再発防止策を Runbook に反映

### **3.9 セキュリティインシデント**

-   Falco/GuardDuty/監査証跡で侵入・権限昇格・証明書漏洩検知
-   該当 Pod/ノード/アカウント隔離、Secrets ローテーション
-   法令・外部通報フローに従い報告

### **3.10 サービスメッシュ障害（Istio/Linkerd）**

-   Kiali でトラフィック/認証/認可/mTLS 状態確認
-   Istio リソース（Gateway/VirtualService/AuthorizationPolicy）設定見直し

### **3.11 外部連携障害**

-   API Gateway/外部 API/サードパーティ疎通テスト
-   リトライ/バッファリング/フェイルオーバー設計の見直し

### **3.12 自動化・バッチ障害**

-   Lambda/EventBridge/バッチ/定期ジョブの失敗ログ確認
-   再実行/スケジューラ修正/通知設定見直し

### **3.13 コスト/リソース枯渇**

-   Cost Explorer/Kubecost/CloudWatch でコスト急増・Quota 超過検知
-   不要リソース停止/削除、Savings Plans/RI/Auto Scaling 見直し

### **3.14 バージョン管理・拡張障害**

-   EKS/Addon/NodeGroup アップグレード失敗時は、事前バックアップ/ロールバック/サポート起票

## 4. 事後レビュー・再発防止

### **インシデント報告書テンプレ**

-   発生日時・検知日時・原因・影響範囲・対応経緯・所要時間・復旧内容・再発防止策・証跡・外部/社内報告履歴

### **再発防止策**

-   Runbook/監視/アラート/CI/CD/設計/運用体制の見直し
-   定期訓練・レビューの実施

## 5. ベストプラクティス・チェックリスト

-   [ ] 全カテゴリのインシデント Runbook を docs/operations.md にも記載・随時訓練
-   [ ] 監査証跡・障害対応履歴は必ず保存・定期レビュー
-   [ ] CSIRT 体制・連絡網・外部通報フローを整備
-   [ ] 事後レビュー・再発防止策は運用/設計/CI/CD/監視に反映
-   [ ] 定期訓練・模擬障害対応を実施

## 6. 参考リンク

-   [AWS インシデント管理公式](https://aws.amazon.com/jp/premiumsupport/incident-management/)
-   [CNCF インシデント対応ベストプラクティス](https://github.com/cncf/tag-security/blob/main/whitepapers/incident-response.md)
-   [JPCERT/CC インシデントハンドリングガイドライン](https://www.jpcert.or.jp/ir/incident-handling.html)
-   [ISMS/PCI DSS インシデント対応要件]

**このドキュメントは、インシデント/障害/セキュリティ/コスト/自動化/バージョン管理/マルチクラスタ/ハイブリッド/監査証跡/Runbook・具体例・コマンド例まで網羅しています。**

[1] preferences.document_format
[2] programming.documentation
