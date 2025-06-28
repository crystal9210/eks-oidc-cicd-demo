# ストレージ設計・運用・バックアップ・監査・障害対応 ドキュメント

このドキュメントは、EKS×AWS 基盤の**ストレージ（S3/EFS/EBS/キャッシュ/バックアップ）設計・運用・監査・障害対応・拡張**を、
**AWS 公式・現場ベストプラクティス・PCI DSS/ISMS/法令・現場の実運用制約まで一切省略せず**、
**設計思想・具体構成・手順・Runbook・CI/CD・監査証跡・障害復旧・拡張方針まで**体系的に記述します。

## 0. ストレージ設計の全体像・責任分界

-   **AWS 責任共有モデル**
    -   AWS は S3/EFS/EBS 等の物理的冗長性・耐久性・暗号化基盤を管理。
    -   ユーザーはデータ配置・ライフサイクル・暗号化設定・アクセス制御・バックアップ/リストア・監査・障害対応・コスト管理の全責任を負う。

## 1. ストレージ種別・用途・選定指針

| 種別        | 主用途                        | 特徴・メリット                | 制約・注意点                     |
| ----------- | ----------------------------- | ----------------------------- | -------------------------------- |
| S3          | オブジェクトストレージ        | 高耐久/低コスト/拡張性        | 一貫性/遅延/権限制御             |
| EFS         | 共有ファイルストレージ        | 複数 Pod/EC2 で同時マウント可 | レイテンシ/コスト/パフォーマンス |
| EBS         | ブロックストレージ            | 高 IOPS/低レイテンシ          | AZ 間移動不可/Pod 再配置制約     |
| FSx         | Windows/Lustre/HPC 用途       | SMB/NFS/Lustre 対応           | 専用用途/コスト                  |
| ElastiCache | キャッシュ（Redis/Memcached） | 高速/一時データ               | 永続化なし/DR 設計必須           |

## 2. S3 設計・運用（具体例・コマンド）

### 2.1 バケット設計

-   **バケット命名規則**
    -   `---`（例: myapp-upload-prod-apne1）
-   **バージョニング・暗号化**
    -   バージョニング有効化、SSE-KMS 必須
-   **ライフサイクル管理**
    -   不要オブジェクトの自動削除/Glacier 移行
-   **アクセス制御**
    -   IAM/バケットポリシーで最小権限、Public アクセス禁止

### 2.2 バケット作成・設定例（Terraform）

```hcl
resource "aws_s3_bucket" "app_upload" {
  bucket = "myapp-upload-prod-apne1"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.s3.arn
      }
    }
  }
  lifecycle_rule {
    id      = "expire-old"
    enabled = true
    expiration {
      days = 365
    }
  }
  force_destroy = false
}
```

### 2.3 バケットポリシー例（最小権限）

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAppRoleAccess",
            "Effect": "Allow",
            "Principal": { "AWS": "arn:aws:iam:::role/app-s3-role" },
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": "arn:aws:s3:::myapp-upload-prod-apne1/*"
        }
    ]
}
```

### 2.4 バックアップ・復旧

-   **S3 クロスリージョンレプリケーション**
    -   バケット設定で DR リージョンへ自動複製
-   **バージョン管理によるリストア**
    -   誤削除時は旧バージョンを復元

### 2.5 監査・コマンド例

```sh
# バケット一覧
aws s3 ls

# オブジェクトアップロード
aws s3 cp file.txt s3://myapp-upload-prod-apne1/

# バージョン一覧・復元
aws s3api list-object-versions --bucket myapp-upload-prod-apne1
aws s3api copy-object --bucket myapp-upload-prod-apne1 --copy-source myapp-upload-prod-apne1/file.txt?versionId=xxxx --key file.txt
```

## 3. EFS/EBS 設計・運用

### 3.1 EFS

-   **用途**：複数 Pod/EC2 で共有が必要な永続ボリューム
-   **マウント例（K8s PVC）**
    ```yaml
    apiVersion: v1
    kind: PersistentVolume
    metadata:
        name: efs-pv
    spec:
        capacity:
            storage: 100Gi
        volumeMode: Filesystem
        accessModes:
            - ReadWriteMany
        persistentVolumeReclaimPolicy: Retain
        csi:
            driver: efs.csi.aws.com
            volumeHandle: fs-xxxx
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
        name: efs-pvc
    spec:
        accessModes:
            - ReadWriteMany
        storageClassName: ""
        resources:
            requests:
                storage: 100Gi
        volumeName: efs-pv
    ```
-   **バックアップ**：EFS バックアップポリシー＋スナップショット＋クロスリージョンコピー

### 3.2 EBS

-   **用途**：各 Pod/EC2 に高 IOPS なブロックストレージが必要な場合
-   **マウント例（K8s PVC）**
    ```yaml
    apiVersion: v1
    kind: PersistentVolume
    metadata:
        name: ebs-pv
    spec:
        capacity:
            storage: 20Gi
        volumeMode: Filesystem
        accessModes:
            - ReadWriteOnce
        persistentVolumeReclaimPolicy: Delete
        csi:
            driver: ebs.csi.aws.com
            volumeHandle: vol-xxxx
    ---
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
        name: ebs-pvc
    spec:
        accessModes:
            - ReadWriteOnce
        storageClassName: gp3
        resources:
            requests:
                storage: 20Gi
    ```
-   **バックアップ**：EBS スナップショット＋ DR リージョンコピー

## 4. キャッシュ・一時ストレージ（ElastiCache/EmptyDir）

### 4.1 ElastiCache（Redis/Memcached）

-   **用途**：セッション/キャッシュ/一時データ
-   **冗長化**：マルチ AZ ＋自動フェイルオーバー
-   **バックアップ**：スナップショット設定＋定期バックアップ
-   **障害時**：再起動/リストア/アプリ再接続（永続化用途には非推奨）

### 4.2 K8s EmptyDir/HostPath

-   **用途**：Pod 内一時ファイル
-   **注意**：ノード障害時は消失、永続化用途には非推奨

## 5. バックアップ・リストア・障害対応 Runbook

### 5.1 S3

-   **バックアップ**：バージョニング＋クロスリージョンレプリケーション
-   **リストア**：旧バージョン復元、誤削除時は管理者承認で復旧
-   **障害時**：バケットポリシー/IAM/暗号化/KMS/監査証跡を即時確認

### 5.2 EFS/EBS

-   **バックアップ**：定期スナップショット＋ DR リージョンコピー
-   **リストア**：スナップショットから新ボリューム作成 →Pod/EC2 へ再アタッチ
-   **障害時**：AWS コンソール/CLI でボリューム状態確認、必要に応じて新規作成＋再マウント

### 5.3 監査・証跡

-   **CloudTrail/Config で全操作を記録**
-   **S3/EFS/EBS のアクセス/変更/復旧は必ず監査証跡に残す**
-   **障害発生時は復旧手順・証跡・原因分析を必ず記録し、事後レビュー**

## 6. 拡張・運用時のチェックリスト

-   [ ] 新サービス/バケット/ボリューム追加時は命名規則・暗号化・監査証跡も設計
-   [ ] バックアップ/スナップショット/レプリケーションは必ず自動化
-   [ ] 監査証跡・アクセス権限は定期的にレビュー
-   [ ] コスト/パフォーマンス/耐久性/復旧性も定期評価
-   [ ] 重大障害時の復旧 Runbook は docs/operations.md にも記載・随時更新

## 7. 参考リンク

-   [AWS S3 公式](https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/Welcome.html)
-   [AWS EFS 公式](https://docs.aws.amazon.com/ja_jp/efs/latest/ug/whatisefs.html)
-   [AWS EBS 公式](https://docs.aws.amazon.com/ja_jp/AWSEC2/latest/UserGuide/AmazonEBS.html)
-   [EKS ストレージベストプラクティス](https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/storage.html)

**このドキュメントは、ストレージ設計・運用・バックアップ・監査・障害対応・拡張・ベストプラクティス・Runbook・公式制約・具体例・コマンド例まで一切省略せず網羅しています。**
