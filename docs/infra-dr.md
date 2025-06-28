# DR（ディザスタリカバリ）・フェイルオーバー設計・運用・監査・訓練 ドキュメント

## 0. DR 戦略の前提

-   **RTO/RPO は必ず明文化**（例：RTO=30 分以内、RPO=5 分以内）
-   **AWS 公式 4 パターン（バックアップ/パイロットライト/ウォームスタンバイ/マルチサイト）から要件に応じて選択**[3][2][8]
-   **全ての構成・手順は IaC（Terraform/Helm/K8s マニフェスト）で再現可能とする**

## 1. DR 対象リソース・設計例（具体構成）

### 1.1 EKS クラスタ（マルチ AZ/マルチリージョン）

-   **マルチ AZ 構成例（eksctl/YAML）**
    ```yaml
    apiVersion: eksctl.io/v1alpha5
    kind: ClusterConfig
    metadata:
        name: my-cluster
        region: ap-northeast-1
        version: "1.29"
    availabilityZones:
        - ap-northeast-1a
        - ap-northeast-1c
        - ap-northeast-1d
    nodeGroups:
        - name: ng-1
          desiredCapacity: 3
          minSize: 2
          maxSize: 4
          availabilityZones:
              - ap-northeast-1a
              - ap-northeast-1c
              - ap-northeast-1d
          instanceType: t3.medium
    ```
-   **マルチリージョン**
    -   `ap-northeast-1`と`ap-southeast-1`等、2 リージョンで同構成の EKS クラスタを IaC で構築
    -   各クラスタに ArgoCD/Flux で同一マニフェストを自動展開[2][6][1]

### 1.2 Route53 フェイルオーバー（DNS レベル）

-   **Route53 フェイルオーバーレコード例（CloudFormation/YAML）**
    ```yaml
    Resources:
        PrimaryRecordSet:
            Type: AWS::Route53::RecordSet
            Properties:
                HostedZoneId:
                Name: my-app.example.com
                Type: A
                Failover: PRIMARY
                AliasTarget:
                    DNSName:
                    HostedZoneId:
                SetIdentifier: Primary
                HealthCheckId:
        SecondaryRecordSet:
            Type: AWS::Route53::RecordSet
            Properties:
                HostedZoneId:
                Name: my-app.example.com
                Type: A
                Failover: SECONDARY
                AliasTarget:
                    DNSName:
                    HostedZoneId:
                SetIdentifier: Secondary
                HealthCheckId:
    ```
-   **Route53 ヘルスチェック**
    -   ALB の/health エンドポイントに対し、2xx/3xx 応答で正常判定
    -   プライマリ障害時、自動でセカンダリ ALB に切替[2]

### 1.3 DB（Aurora Global DB/RDS/DynamoDB）

-   **Aurora Global Database 構成例**
    -   プライマリ：ap-northeast-1、セカンダリ：ap-southeast-1
    -   自動レプリケーション＋セカンダリ昇格（failover/failback は Lambda/手動/自動）[7]
-   **RDS クロスリージョンリードレプリカ**
    -   プライマリ障害時、リードレプリカを昇格し、アプリの接続先を切替
-   **DynamoDB グローバルテーブル**
    -   複数リージョンで同一データを自動同期

### 1.4 S3/EFS/EBS

-   **S3 クロスリージョンレプリケーション**
    -   バケット設定で DR リージョンへ自動複製
-   **EFS/EBS スナップショット**
    -   定期スナップショット＋ DR リージョンへのコピー[1][5]

### 1.5 Secrets/Config

-   **AWS Secrets Manager/SSM はクロスリージョンレプリケーション設定**
-   **K8s Secret は External Secrets Operator で自動同期**

## 2. DR 運用 Runbook（正常系・異常系）

### 2.1 正常系：DR 訓練・DR テスト

1. **DR 先リージョンに EKS クラスタを IaC で新規構築**
2. **ArgoCD/Flux で全マニフェストを自動展開**
3. **DB/S3/EFS/Secrets を最新スナップショット/レプリカから復元**
4. **Route53 フェイルオーバー設定をテスト用に切替**
5. **アプリ疎通・バッチ・監視・監査証跡の動作確認**
6. **所要時間・手順・問題点を記録し Runbook を改善**

### 2.2 異常系：障害発生時のフェイルオーバー

#### AZ 障害時

1. **CloudWatch/ALB/Route53 で AZ 障害を自動検知**
2. **EKS ノード/Pod は自動で正常 AZ に再スケジューリング**
3. **RDS/Aurora は自動フェイルオーバー**
4. **Pod/バッチ/ジョブ/外部 API 等の疎通確認**
5. **監査証跡に障害・対応を記録**

#### リージョン障害時

1. **CloudWatch/Route53/監視で障害を検知**
2. **DR リージョンで EKS/DB/S3/Secrets を IaC ＋スナップショットから復元**
3. **Route53 フェイルオーバーで DR 先 ALB に切替**
4. **ArgoCD/Flux でアプリ/バッチ/監視/監査証跡を復旧**
5. **疎通確認・監査証跡記録・事後レビュー**

## 3. CI/CD・監査・自動化

-   **全 DR 構成/手順は IaC/Git 管理＋ PR レビュー＋ CI/CD 自動テスト**
-   **DR 訓練/リハーサルはテスト用リージョンで自動デプロイ/リストア/疎通確認**
-   **CloudTrail/Config/監査証跡は DR 時も必ず保存・エクスポート**
-   **DR 訓練・障害対応の全操作は監査証跡として記録・定期レビュー**

## 4. 具体的なコマンド・手順例

### 4.1 EKS クラスタ復旧

```sh
# DRリージョンでEKSクラスタをIaCで新規構築
eksctl create cluster -f eks-cluster-dr.yaml

# ArgoCDで全マニフェストを自動展開
argocd cluster add
argocd app sync --all

# DBリストア（Aurora Global DBの場合）
aws rds failover-db-cluster --db-cluster-identifier  --target-db-instance-arn

# S3クロスリージョンレプリケーション設定
aws s3api put-bucket-replication --bucket  --replication-configuration file://replication.json

# Route53フェイルオーバー切替
aws route53 change-resource-record-sets --hosted-zone-id  --change-batch file://failover.json
```

### 4.2 監査証跡・復旧確認

```sh
# CloudTrailでDR時の操作を確認
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=FailoverDBCluster

# DR先クラスタのPod/サービス疎通を確認
kubectl get pods -A
kubectl get svc -A
kubectl logs  -n
```

## 5. DR 訓練・障害対応の監査・レビュー

-   **訓練/障害時は必ず手順・判断・所要時間・問題点を監査ログに記録**
-   **事後レビューで Runbook・IaC・監査証跡・監視/アラート設計を改善**

## 6. ベストプラクティス・チェックリスト

-   [ ] RTO/RPO・DR 対象・手順・運用責任を明文化
-   [ ] EKS/DB/S3/EFS/Secrets 等はクロスリージョン冗長＋ IaC 管理
-   [ ] Route53 フェイルオーバーは必ず HealthCheck ＋自動切替
-   [ ] DR 訓練・障害対応の全操作は監査証跡として保存・定期レビュー
-   [ ] DR 訓練は年 1 回以上、障害シナリオごとに必ず実施

## 7. 参考リンク

-   [AWS 公式 DR 戦略](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)
-   [EKS マルチリージョン DR 実装例 (AWS Blog)][1]
-   [EKS DR ベストプラクティス][2][4][5][6][7]
-   [Aurora Global DB DR 設計][7]

**このドキュメントは、現場で即使える「DR/フェイルオーバー/障害復旧/監査/訓練/Runbook/コマンド例」まで完全網羅しています。**

[1] https://aws.amazon.com/blogs/containers/multi-region-disaster-recovery-with-amazon-eks-and-amazon-efs-for-stateful-workloads/
[2] https://dev.to/aws-builders/ensuring-disaster-recovery-and-high-availability-in-aws-eks-best-practices-4j7l
[3] https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html
[4] https://docs.aws.amazon.com/eks/latest/userguide/disaster-recovery-resiliency.html
[5] https://trilio.io/kubernetes-disaster-recovery/eks-backup/
[6] https://blogs.halodoc.io/aws-eks-disaster-recovery-strategy-2/
[7] https://github.com/aws-solutions-library-samples/guidance-for-disaster-recovery-using-amazon-aurora
[8] https://opsiocloud.com/in/blogs/aws-disaster-recovery-plan-a-step-by-step-guide-opsio/
[9] preferences.information_presentation
[10] preferences.feedback_format
[11] preferences.instruction_format
[12] programming.implementation
[13] preferences.communication
