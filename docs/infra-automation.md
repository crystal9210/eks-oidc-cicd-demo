# 運用自動化・CI/CD・自動修復・監査・拡張 詳細ドキュメント＆手順書

このドキュメントは、**AWS×EKS×Kubernetes 基盤の運用自動化（CI/CD/自動修復/自動監査/スクリプト/自動 Runbook/拡張）**を、
**AWS 公式・現場ベストプラクティス・法令・実運用制約まで**、
**初心者でもすぐ実践できるよう、段階的な手順・具体的なユースケース・数値例・コマンド・運用フロー・自動化設計・Runbook まで体系的に記述します。**

## 0. 運用自動化の全体像

-   **目的**:
    -   手作業の排除、人的ミス防止、運用品質向上、障害復旧の迅速化、コスト削減、セキュリティ強化
-   **主な対象**:
    -   CI/CD（GitHub Actions/ArgoCD）、自動監査（静的解析/ポリシー）、リソース自動修復、スケジューリング、通知、運用 Runbook の自動化、EKS Auto Mode

## 1. 主要ユースケース別・自動化パターン

| ユースケース                               | 自動化内容例                                                          | 使用サービス/ツール        | 具体例・数値・コマンド例                           |
| ------------------------------------------ | --------------------------------------------------------------------- | -------------------------- | -------------------------------------------------- |
| 高可用性アプリの自動運用                   | マルチ AZ/Auto Scaling/Pod 自己修復                                   | EKS, ALB, HPA, PDB         | Replica=3, HPA: min=2, max=10, PDB: minAvailable=2 |
| マイクロサービス CI/CD                     | PR→ テスト → ビルド → イメージ Push→ マニフェスト Apply→ 自動デプロイ | GitHub Actions, ArgoCD     | 例：main マージで 5 分以内に自動本番反映           |
| セキュリティ・監査自動化                   | 静的解析/ポリシーチェック/脆弱性スキャン/監査証跡自動保存             | Trivy, Checkov, OPA, Falco | PR ごとに trivy scan, opa test, falco event 監査   |
| サーバレス/バッチ/AI/ML の自動スケール     | Fargate/EKS Auto Mode/Spot 活用/ノード自動追加削除                    | Fargate, EKS Auto Mode     | GPU ノード自動増減、バッチ Spot 活用でコスト 30%減 |
| コスト最適化・夜間停止                     | EventBridge/Lambda で夜間開発環境自動停止/再開                        | EventBridge, Lambda        | 例：22:00-8:00 で EC2/EKS ノード自動停止/開始      |
| 自動バックアップ・リストア                 | RDS/EFS/EBS/S3 の定期スナップショット＋自動リストア Runbook           | AWS Backup, Lambda, Shell  | RDS: 1 日 1 回自動スナップショット、復旧 10 分以内 |
| 障害検知・自動修復                         | Pod/EC2 障害時の自動再起動/再スケジュール/通知                        | K8s, Lambda, CloudWatch    | Pod 障害時自動再起動、EC2 障害時 Lambda で再起動   |
| ハイブリッド/エッジ/マルチクラスタ自動運用 | EKS Anywhere/Auto Mode/Outposts でオンプレ/クラウド一元自動化         | EKS Anywhere, Auto Mode    | クラウド/オンプレ混在環境を同じ CI/CD で管理       |

## 2. CI/CD 自動化詳細手順・サンプル

### 2.1 GitHub Actions による CI/CD（Go サービス例）

```yaml
name: CI/CD Pipeline

on:
    push:
        branches: [main]
    pull_request:

jobs:
    build:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - name: Set up Go
              uses: actions/setup-go@v5
              with:
                  go-version: "1.21"
            - name: Build
              run: go build -v ./...
            - name: Test
              run: go test -v ./...
            - name: Docker Build & Push
              uses: docker/build-push-action@v5
              with:
                  context: .
                  push: true
                  tags: ${{ secrets.DOCKER_REGISTRY }}/user-service:${{ github.sha }}
            - name: Deploy to EKS
              env:
                  KUBECONFIG: ${{ secrets.KUBECONFIG }}
              run: |
                  kubectl apply -f infra/k8s/user-service/deployment.yaml
```

-   **CI 所要時間目安**：ビルド～デプロイまで約 5 ～ 10 分

### 2.2 ArgoCD による GitOps 自動デプロイ

-   `cicd/argocd-apps/user-service-app.yaml` で Git リポジトリ監視
-   PR マージ → 自動で K8s 反映、失敗時は Slack 通知

## 3. 静的解析・セキュリティ自動化

### 3.1 Trivy による脆弱性スキャン

```yaml
name: Trivy Scan

on: [push, pull_request]

jobs:
    trivy:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - name: Run Trivy
              uses: aquasecurity/trivy-action@v0.16.0
              with:
                  image-ref: ${{ secrets.DOCKER_REGISTRY }}/user-service:${{ github.sha }}
```

-   **例：CVSS 7.0 以上の脆弱性が 1 件でもあれば CI を Fail に**

### 3.2 OPA Gatekeeper によるポリシー自動チェック

-   `cicd/opa-policies/deny-privileged.rego` で特権 Pod 禁止
-   PR 時に自動テストで違反検知 →Fail

## 4. EKS Auto Mode によるクラスタ自動運用

-   **EKS Auto Mode の特徴**[2][5][6]:
    -   ノード自動増減・コスト最適化・パッチ/アップグレード自動化・セキュリティ強化
    -   例：Pod 数増加時に自動で EC2 ノード追加、負荷減時は自動削除
    -   21 日ごとにノード自動更新でセキュリティ維持
-   **導入手順例**
    ```bash
    eksctl create cluster --auto-mode --name prod-auto --region ap-northeast-1
    ```
-   **ユースケース**:
    -   Web アプリ：トラフィック急増時に自動スケール
    -   AI/ML：GPU ノード自動追加・削除
    -   バッチ処理：Spot インスタンス活用でコスト 30%以上削減[6]

## 5. 障害検知・自動修復 Runbook

### 5.1 K8s 自己修復

-   **Deployment/StatefulSet の Replica 管理で Pod 障害時に自動再スケジューリング**
-   **HPA で CPU70%超時に Pod 自動増加（例：min=2, max=10）**

### 5.2 Lambda ＋ EventBridge による EC2 自動再起動

1. **EventBridge で「EC2 ステータスチェック失敗」イベント検知**
2. **Lambda で該当インスタンスを自動再起動**
    ```python
    import boto3
    def lambda_handler(event, context):
        ec2 = boto3.client('ec2')
        instance_id = event['detail']['instance-id']
        ec2.reboot_instances(InstanceIds=[instance_id])
    ```
3. **実績値例**：障害検知～自動復旧まで平均 3 分以内

## 6. バックアップ・リストア・定期タスク自動化

### 6.1 RDS 自動バックアップ

-   **毎日 1 回自動スナップショット、保存期間 7 日**
-   **復旧手順：AWS コンソールまたは CLI でスナップショットから新 DB 作成**
    ```bash
    aws rds restore-db-instance-from-db-snapshot --db-instance-identifier newdb-202506 --db-snapshot-identifier rds:prod-2025-06-30-06-00
    ```

### 6.2 K8s CronJob によるバッチ自動化

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
    name: daily-report
spec:
    schedule: "0 2 * * *"
    jobTemplate:
        spec:
            template:
                spec:
                    containers:
                        - name: report
                          image: myapp/report:latest
                          command: ["python", "generate_report.py"]
                    restartPolicy: OnFailure
```

-   **実績例**：毎日 2:00 に自動実行、失敗時は Slack 通知

## 7. 通知・エスカレーション自動化

-   **Prometheus Alertmanager/CloudWatch Alarms で障害・アラートを Slack/SNS/メールに自動通知**
-   **例：Pod 再起動回数>5、EC2 コスト急増時、RDS バックアップ失敗時に即時通知**
-   **通知例（Slack）**：
    ```
    [ALERT] user-service Podが10分間で5回以上再起動しました（prod-cluster）
    ```

## 8. 監査・Runbook・ベストプラクティス

-   **すべての自動化スクリプト・CI/CD・監査設定は IaC/Git 管理＋ PR レビュー＋ CI/CD 自動テスト**
-   **自動化手順・障害対応 Runbook は docs/operations.md にも記載・随時更新**
-   **自動化の監査証跡は CloudTrail/Config/K8s Audit で長期保存**

## 9. 主要自動化ツール・サービスまとめ

| 領域                  | 推奨ツール/サービス        | 具体的な使い方・特徴例                       |
| --------------------- | -------------------------- | -------------------------------------------- |
| CI/CD                 | GitHub Actions, ArgoCD     | PR→ 自動テスト → 自動デプロイ                |
| 静的解析/監査         | Trivy, Checkov, OPA, Falco | PR ごとに自動スキャン・違反時 Fail           |
| クラスタ自動運用      | EKS Auto Mode, Karpenter   | ノード自動増減・アップグレード・コスト最適化 |
| バッチ/定期タスク     | K8s CronJob, EventBridge   | 毎日/毎時/夜間など定期自動実行               |
| 障害自動修復          | Lambda, CloudWatch, K8s    | 障害検知 → 自動再起動/再スケジューリング     |
| 通知/エスカレーション | Alertmanager, SNS, Slack   | 障害・異常時に即時通知・自動エスカレーション |

## 10. チェックリスト

-   [ ] すべての運用自動化は Git 管理＋ CI/CD 自動テスト
-   [ ] 障害・リソース枯渇・セキュリティ異常は自動通知・自動修復
-   [ ] 定期タスク・バッチは EventBridge/K8s CronJob で自動化
-   [ ] 自動化スクリプト・Runbook は常に最新化・運用訓練
-   [ ] 監査証跡・自動化ログは必ず長期保存

## 11. 参考リンク

-   [AWS EKS 運用自動化ユースケース（公式）][1][2][5][6]
-   [GitHub Actions 公式](https://docs.github.com/ja/actions)
-   [ArgoCD 公式](https://argo-cd.readthedocs.io/)
-   [AWS Lambda 公式](https://docs.aws.amazon.com/ja_jp/lambda/latest/dg/welcome.html)
-   [Kubernetes CronJob 公式](https://kubernetes.io/ja/docs/concepts/workloads/controllers/cron-jobs/)

**このドキュメントは、EKS/Kubernetes 運用自動化の主要ユースケース・具体例・数値・手順・コマンド・運用フロー・拡張・障害対応・監査・ベストプラクティス・Runbook まで網羅しています。**

[1] https://docs.aws.amazon.com/eks/latest/userguide/common-use-cases.html
[2] https://docs.aws.amazon.com/eks/latest/userguide/automode.html
[3] https://www.techtarget.com/searchitoperations/tip/Kubernetes-automation-Use-cases-and-tools-to-know
[4] https://rafay.co/the-kubernetes-current/optimizing-amazon-eks-advanced-configuration-scaling-and-cost-management-strategies/
[5] https://aws.amazon.com/eks/auto-mode/
[6] https://dev.to/aws-builders/aws-eks-auto-mode-automating-kubernetes-cluster-management-1cek
[7] https://repost.aws/articles/ARP74Xj00HRkGHaiN1HrI52Q/aws-re-invent-2024-amazon-eks-for-edge-and-hybrid-use-cases
[8] https://notes.kodekloud.com/docs/AWS-EKS/EKS-Fundamentals/Common-Use-Cases
