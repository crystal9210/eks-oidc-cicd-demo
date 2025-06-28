# 移行設計・データ/システム移行・リハーサル・監査・障害対応 超詳細ドキュメント＆手順書

このドキュメントは、**AWS×EKS×Kubernetes 基盤の移行（オンプレ → クラウド、旧環境 → 新環境、データ・アプリ・ネットワーク・CI/CD・監査）**を、
**AWS 公式・現場ベストプラクティス・法令・実運用制約まで一切省略せず**、
**初心者でもすぐ実践できるよう、段階的な手順・具体例・コマンド・運用フロー・リハーサル・カットオーバー・障害対応・Runbook まで体系的に記述します。**

## 0. 移行プロジェクト全体像

-   **目的**: サービス停止/リスク最小化、データ・アプリ・ネットワーク・監査証跡の完全移行
-   **主な対象**:
    -   オンプレ →AWS（EKS, RDS, S3, etc.）
    -   旧 K8s クラスタ → 新 EKS クラスタ
    -   DB/ストレージ/ファイル/Secrets/CI/CD/監査証跡

## 1. 移行計画・設計フェーズ

### 1.1 現状調査・棚卸し

-   サービス/DB/ストレージ/ネットワーク/監査証跡/CI/CD/ジョブ/バッチ/外部連携を全てリスト化
-   例:
    | 項目 | 現行環境 | 新環境 | 備考 |
    |--------------|------------------|------------------|-----------------------|
    | Web | オンプレ VM | EKS | Go/Node/Python 混在 |
    | DB | MySQL5.7 | RDS/Aurora MySQL | バージョン差異注意 |
    | ファイル | NFS | S3/EFS | 1TB/日常増分 10GB |
    | Secrets | 手動 env ファイル | Secrets Manager | Git 秘匿必須 |
    | 監査証跡 | ローカル syslog | CloudTrail/S3 | 7 年保存 |

### 1.2 移行方式の選定

| 項目     | 推奨方式              | 具体例・コマンド例                               |
| -------- | --------------------- | ------------------------------------------------ |
| DB       | DMS/スナップショット  | DMS でレプリケーション、最終カットオーバーで切替 |
| ファイル | AWS DataSync/rsync/S3 | DataSync で全量 → 増分同期、rsync で差分同期     |
| アプリ   | Blue/Green Deploy     | 新旧並行稼働、Route53/ALB で段階切替             |
| CI/CD    | GitHub Actions/ArgoCD | 新リポジトリ/パイプラインに移行                  |
| Secrets  | External Secrets      | Secrets Manager/SSM に移行、K8s 自動同期         |

## 2. データ移行手順（DB/ファイル/Secrets）

### 2.1 RDS/Aurora への DB 移行

#### ステップ 1: DMS レプリケーションインスタンス作成

```bash
aws dms create-replication-instance --replication-instance-identifier dms-migration --allocated-storage 100
```

#### ステップ 2: ソース/ターゲットエンドポイント作成

```bash
aws dms create-endpoint --endpoint-identifier src-mysql --engine-name mysql --server-name  ...
aws dms create-endpoint --endpoint-identifier tgt-rds --engine-name mysql --server-name  ...
```

#### ステップ 3: 移行タスク作成（全量＋増分）

```bash
aws dms create-replication-task --replication-task-identifier db-migrate-task --migration-type full-load-and-cdc ...
```

#### ステップ 4: カットオーバー

-   サービス停止 → 最終増分同期 →DNS 切替 → 新環境でサービス再開

### 2.2 S3/EFS へのファイル移行

#### DataSync ジョブ例

```bash
aws datasync create-location-nfs --server-hostname  --subdirectory /data
aws datasync create-location-s3 --s3-bucket-arn arn:aws:s3:::my-bucket
aws datasync create-task --source-location-arn ... --destination-location-arn ...
aws datasync start-task-execution --task-arn ...
```

#### rsync 例（小規模/手動用）

```bash
rsync -avz /mnt/nfs/ user@ec2:/mnt/efs/
```

### 2.3 Secrets/Config 移行

-   旧 env ファイル/ConfigMap/Secret を Secrets Manager/SSM に登録
-   External Secrets Operator で K8s Secret に自動同期

## 3. アプリ/CI/CD/監査証跡移行

### 3.1 アプリ Blue/Green 移行

-   新 EKS クラスタに新バージョンをデプロイ（旧環境と並行稼働）
-   Route53/ALB でトラフィックを段階的に切替（例: 10%→50%→100%）
-   切替後、旧環境を停止

### 3.2 CI/CD パイプライン移行

-   新 GitHub リポジトリ作成、Actions/ArgoCD パイプラインを新環境用に再構築
-   旧パイプラインはカットオーバー後に停止

### 3.3 監査証跡移行

-   旧 syslog/ログを S3/CloudTrail にエクスポート
-   新環境では CloudTrail/Config/K8s Audit/Falco を必ず有効化

## 4. リハーサル・カットオーバー・テスト

### 4.1 リハーサル

-   移行手順書通りにテスト環境で移行を実施
-   データ/アプリ/監査証跡の整合性・疎通確認
-   所要時間・問題点を記録し Runbook を改善

### 4.2 カットオーバー本番

1. 事前アナウンス（ユーザー/運用/経営層）
2. サービス停止（必要ならメンテナンス画面表示）
3. 最終データ同期・DNS/ALB 切替
4. 新環境で疎通・監査証跡確認
5. 旧環境停止・監査ログ保存

## 5. 障害対応・ロールバック Runbook

### 5.1 移行失敗時

-   旧環境に DNS/ALB を即時切戻し
-   新環境の変更をロールバック（DB/ファイル/Secrets/CI/CD）
-   障害原因を記録し、再発防止策を Runbook に反映

### 5.2 データ不整合・欠損時

-   S3/DB スナップショット/監査証跡からリストア
-   差分データは手動/自動で再同期

## 6. 監査・ベストプラクティス・チェックリスト

-   [ ] すべての移行手順・リハーサル・障害対応は docs/operations.md にも記録
-   [ ] 監査証跡（CloudTrail/Config/K8s Audit）は移行中も必ず保存
-   [ ] 旧環境のデータ/証跡/設定は一定期間アーカイブ保存
-   [ ] 移行後は必ず性能/可用性/監査/コスト/セキュリティを再評価
-   [ ] 移行 Runbook は常に最新化・運用訓練

## 7. 参考リンク

-   [AWS DMS 公式](https://docs.aws.amazon.com/ja_jp/dms/latest/userguide/Welcome.html)
-   [AWS DataSync 公式](https://docs.aws.amazon.com/ja_jp/datasync/latest/userguide/what-is-datasync.html)
-   [EKS 移行ベストプラクティス](https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/migration.html)
-   [Kubernetes Blue/Green Deploy 公式](https://kubernetes.io/ja/docs/concepts/cluster-administration/manage-deployment/)

**このドキュメントは、移行設計・データ/システム移行・リハーサル・カットオーバー・監査・障害対応・Runbook・具体例・コマンド例まで網羅しています。**
