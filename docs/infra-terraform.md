# Terraform 運用・設計・拡張 ドキュメント

このドキュメントは、EKS×Istio× マイクロサービス基盤の**AWS リソース（VPC/EKS/ALB/RDS/ACM/IAM/S3/CloudWatch 等）を Terraform で運用・拡張・監査するための設計・運用・障害対応・拡張手順**を、**AWS 公式・現場ベストプラクティスに基づき、一切省略せず**記述します。

## 1. ディレクトリ・State 設計

### 1.1 ディレクトリ分割例（マルチクラスタ/マルチアカウント対応）

```
infra/
  ├── cluster-prod-japan/
  │     └── terraform/
  ├── cluster-prod-eu/
  │     └── terraform/
  └── shared/
        └── terraform-modules/
```

-   **各クラスタ/環境ごとに独立した terraform ディレクトリ・State を管理**
-   **共通モジュールは shared/terraform-modules/へ集約**

### 1.2 State ファイル管理・Lock 戦略

-   **State ファイルは S3+KMS 暗号化+State Lock（DynamoDB）で管理**
-   **State はクラスタ/環境単位で完全分離（prod-japan, prod-eu, dev 等）**
-   **State 破損時の復旧 Runbook（手順書）は本ファイル末尾に記載**

#### 例：backend 設定

```hcl
terraform {
  backend "s3" {
    bucket         = "eks-oidc-cicd-demo-tfstate-prod-japan"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "eks-oidc-cicd-demo-tfstate-lock"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-1:xxxx:key/xxxx"
  }
}
```

## 2. IaC 設計・モジュール化

### 2.1 モジュール設計

-   **VPC/EKS/ALB/RDS/ACM/IAM/S3/CloudWatch 等は全て module 化**
-   **module は shared/terraform-modules/に配置し、各クラスタから呼び出し**
-   **バージョン管理・リリースノートも shared/terraform-modules/で管理**

### 2.2 主要リソースの責務・設計例

-   **VPC**:
    -   Public/Private/Isolated サブネット分離、NAT Gateway 冗長化、Flow Logs 有効化
-   **EKS**:
    -   Multi-AZ, IRSA, OIDC, Pod Security Group, Control Plane Logging 有効化
-   **ALB**:
    -   HTTPS 終端、WAF 連携、ALB アクセスログ S3 保存
-   **RDS/Aurora**:
    -   Multi-AZ、リードレプリカ、Auto Minor Version Upgrade、暗号化
-   **IAM**:
    -   最小権限原則、AssumeRole、サービスごとに Role 分離
-   **S3**:
    -   バケットポリシー、暗号化、バージョニング、アクセスログ
-   **CloudWatch**:
    -   メトリクス/ログ/アラーム、監査証跡集約

## 3. 運用手順（正常系・異常系）

### 3.1 初期セットアップ（正常系）

1. **AWS CLI 認証**
   `aws configure`で適切な IAM 権限をセット
2. **backend 設定確認**
   S3 バケット・DynamoDB テーブル・KMS キーを事前作成
3. **初期化**
    ```sh
    terraform init
    ```
4. **Plan/Apply**
    ```sh
    terraform plan -out=tfplan
    terraform apply tfplan
    ```
5. **State ファイルの S3/Lock/DynamoDB を確認**

### 3.2 変更反映（正常系）

1. **コード修正（例：RDS インスタンスタイプ変更）**
2. **Plan/Apply**
    ```sh
    terraform plan -out=tfplan
    terraform apply tfplan
    ```
3. **Apply 後の差分・リソース状態を必ず確認**

### 3.3 モジュール/バージョン更新（正常系）

1. **shared/terraform-modules/でバージョンアップ**
2. **各クラスタで module バージョンを指定し直す**
3. **Plan/Apply で差分・影響範囲を確認**

### 3.4 異常系（障害時・復旧手順）

#### State ファイル破損・競合

1. **S3 バケット/Lock テーブルの状態確認**
2. **State ファイルを S3 からダウンロードしローカルバックアップ**
3. **`terraform state`コマンドで手動修復（import/move/rm/add）**
4. **必要なら`terraform force-unlock`で Lock 解除**
5. **復旧後は必ず全リソースの現物と State の一致を確認**

#### Apply 失敗・リソース破損

1. **失敗リソースを`terraform state`で import し直す**
2. **AWS Console で現物リソースの状態を確認**
3. **必要なら手動でリソース削除/再作成 →State 再 import**

#### IAM/Secret/ネットワーク設定ミス

1. **誤設定発覚時は即時`terraform apply`で修正**
2. **重大インシデントは手動で一時的に権限/SG/Secret を修正 → 後で IaC に反映**

## 4. セキュリティ・監査・コンプライアンス

-   **すべての変更は PR レビュー必須（GitHub Actions/CI で自動 Plan/Checkov/Trivy）**
-   **CloudTrail/Config で全リソース変更・API コールを監査証跡として保存**
-   **KMS で State/Secret/リソース暗号化、KMS キーのローテーション設計も明記**
-   **IAM/SG/Secret 等の重大リソースは変更時に Slack/メール/JIRA で自動通知**

## 5. 拡張・運用時のチェックリスト

-   [ ] 新クラスタ/アカウント追加時はディレクトリ・State・backend 設定を分離
-   [ ] モジュール追加/更新時は shared/terraform-modules/でバージョン管理
-   [ ] 監査証跡・State ファイルは定期的にバックアップ・検証
-   [ ] 重大障害時の復旧 Runbook は本ファイル・docs/operations.md に記載・随時更新

## 6. 参考リンク・外部標準

-   [Terraform 公式](https://www.terraform.io/)
-   [AWS 公式 IaC ベストプラクティス](https://docs.aws.amazon.com/ja_jp/wellarchitected/latest/framework/devops-automate-infrastructure.html)
-   [EKS IaC 設計ガイド](https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/infrastructure-as-code.html)
-   [Terraform State 運用ガイド](https://developer.hashicorp.com/terraform/language/state)

**このドキュメントは、現場最高水準の IaC 運用・拡張・監査・障害対応・セキュリティ・コンプライアンスまでまとめています。**
