# データベース設計・運用・監査・バックアップ・障害対応 詳細ドキュメント＆手順書

このドキュメントは、**AWS×EKS×Kubernetes 基盤の RDS/Aurora/DynamoDB/ElastiCache 等の DB 設計・運用・監査・バックアップ・リストア・障害対応・拡張**を、
**AWS 公式・現場ベストプラクティス・法令・実運用制約まで一切省略せず**、
**初心者でもすぐ実践できるよう、段階的な手順・具体例・コマンド・運用フロー・障害対応・Runbook まで体系的に記述します。**

## 0. DB 設計・選定方針

-   **目的**:
    -   高可用性・耐障害性・拡張性・セキュリティ・監査性・コスト最適化
-   **主な選択肢**:
    -   RDS/Aurora（MySQL/PostgreSQL/…）、DynamoDB、ElastiCache（Redis/Memcached）、EFS/EBS（ファイル DB 用途）

## 1. RDS/Aurora 設計・運用

### 1.1 マルチ AZ・自動フェイルオーバー設計

-   **本番は必ず Multi-AZ 構成＋自動フェイルオーバー有効化**
-   **Aurora は Global DB/クロスリージョンリードレプリカも検討**

#### サンプル: Terraform で Aurora MySQL Multi-AZ 構築

```hcl
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "prod-aurora"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.04.1"
  master_username        = "admin"
  master_password        = var.db_master_password
  backup_retention_period= 7
  preferred_backup_window= "02:00-03:00"
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.db.arn
}
```

### 1.2 DB パラメータ・接続制御

-   **パラメータグループで SQL モード・タイムゾーン・接続数等を明示設定**
-   **SG/NetworkPolicy で最小権限通信のみ許可（例：app サブネット →DB サブネット）**
-   **IAM DB 認証（RDS/Aurora）も活用可能**

### 1.3 バックアップ・リストア

#### 自動バックアップ

-   **毎日 1 回自動スナップショット、保存期間 7 日以上推奨**
-   **手動スナップショットも定期取得（本番リリース/大規模変更前）**

#### バックアップ取得コマンド例

```bash
aws rds create-db-snapshot --db-instance-identifier prod-aurora-1 --db-snapshot-identifier prod-aurora-snap-20250630
```

#### リストア手順

```bash
aws rds restore-db-instance-from-db-snapshot --db-instance-identifier prod-aurora-restore --db-snapshot-identifier prod-aurora-snap-20250630
```

### 1.4 監査・証跡・セキュリティ

-   **監査ログ（mysql_audit/audit_log）有効化＋ S3/CloudWatch Logs 転送**
-   **KMS 暗号化必須、証跡アクセスも最小権限化**
-   **パスワード/Secrets は AWS Secrets Manager で管理、K8s は External Secrets で自動同期**

## 2. DynamoDB 設計・運用

### 2.1 テーブル設計・パーティション戦略

-   **アクセスパターンを明確化し、パーティションキー/ソートキー設計**
-   **Global Secondary Index（GSI）/Local Secondary Index（LSI）活用**
-   **オンデマンド/プロビジョンドスループット選択、Auto Scaling 有効化**

#### テーブル作成例（CLI）

```bash
aws dynamodb create-table --table-name user-table \
  --attribute-definitions AttributeName=UserID,AttributeType=S \
  --key-schema AttributeName=UserID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### 2.2 バックアップ・リストア

-   **Point-in-Time Recovery（PITR）有効化で最大 35 日間の任意時点リストア**
-   **オンデマンドバックアップも定期取得**

#### バックアップ取得例

```bash
aws dynamodb create-backup --table-name user-table --backup-name user-table-backup-20250630
```

#### リストア例

```bash
aws dynamodb restore-table-from-backup --target-table-name user-table-restore --backup-arn arn:aws:dynamodb:ap-northeast-1:xxxx:table/user-table/backup/xxxx
```

### 2.3 監査・セキュリティ

-   **CloudTrail で全操作証跡化**
-   **KMS 暗号化、IAM 最小権限設計**

## 3. ElastiCache（Redis/Memcached）設計・運用

### 3.1 冗長化・フェイルオーバー

-   **Redis はマルチ AZ ＋自動フェイルオーバー必須**
-   **Memcached はクラスターモード有効化**

### 3.2 バックアップ・リストア

-   **Redis はスナップショット自動取得＋手動バックアップ**
-   **障害時はスナップショットから新クラスタ作成**

#### バックアップ取得例

```bash
aws elasticache create-snapshot --cache-cluster-id prod-redis --snapshot-name prod-redis-snap-20250630
```

### 3.3 監査・セキュリティ

-   **SG/NetworkPolicy で接続元制限**
-   **KMS 暗号化、CloudTrail で操作証跡化**

## 4. DB 運用・監査・障害対応 Runbook

### 4.1 定期運用

-   バックアップ/監査ログ/パラメータ/接続数/性能/コストの定期レビュー
-   パッチ/バージョンアップは事前検証＋本番反映

### 4.2 障害対応

#### DB インスタンス障害時

1. **CloudWatch アラートで障害検知**
2. **自動フェイルオーバー確認（Multi-AZ/Global DB）**
3. **必要に応じて手動フェイルオーバー/リストア**
4. **監査証跡・障害対応履歴を記録**

#### データ不整合・誤削除時

1. **スナップショット/PITR からリストア**
2. **アプリ/ユーザーへの影響範囲確認**
3. **再発防止策を Runbook・設計に反映**

## 5. ベストプラクティス・チェックリスト

-   [ ] 本番 DB は必ず Multi-AZ/自動フェイルオーバー
-   [ ] バックアップ/PITR/監査ログは必ず有効化・長期保存
-   [ ] KMS 暗号化/IAM 最小権限/Secrets Manager 連携を徹底
-   [ ] DB 設計/運用/障害対応 Runbook は docs/operations.md にも記載・随時訓練
-   [ ] 監査証跡・自動化ログは必ず長期保存

## 6. 参考リンク

-   [AWS RDS/Aurora 公式](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Welcome.html)
-   [AWS DynamoDB 公式](https://docs.aws.amazon.com/ja_jp/amazondynamodb/latest/developerguide/Introduction.html)
-   [AWS ElastiCache 公式](https://docs.aws.amazon.com/ja_jp/AmazonElastiCache/latest/red-ug/WhatIs.html)
-   [Kubernetes External Secrets Operator](https://external-secrets.io/)

**このドキュメントは、DB 設計・運用・監査・バックアップ・リストア・障害対応・ベストプラクティス・Runbook・具体例・コマンド例まで網羅しています。**
