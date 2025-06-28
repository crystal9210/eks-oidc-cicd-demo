# AI/ML 基盤設計・SageMaker・Bedrock・推論基盤・MLOps・生成 AI 運用 詳細ドキュメント＆Runbook 集

このドキュメントは、**AWS×EKS×Kubernetes 基盤の AI/ML/生成 AI 基盤設計・運用・監査・障害対応・拡張**を、
**AWS 公式・現場ベストプラクティス・法令・実運用制約まで一切省略せず**、
**初心者でもすぐ実践できるよう、段階的な手順・具体例・コマンド・運用フロー・Runbook まで体系的に記述します。**

## 0. AI/ML 基盤設計の全体像

-   **目的**
    -   AI/ML/生成 AI モデルの開発・学習・推論・運用・監査を安定・安全・高効率に実現
-   **主な構成要素**
    -   データ収集・前処理、学習基盤、モデル管理、推論基盤、MLOps、監査・セキュリティ

## 1. AWS AI/ML サービス選定と構成

| サービス名     | 主な用途                        | 具体例・特徴                                    |
| -------------- | ------------------------------- | ----------------------------------------------- |
| SageMaker      | 学習・推論・MLOps               | Jupyter, AutoML, パイプライン, モデルデプロイ   |
| Bedrock        | 生成 AI API/推論/埋め込み       | Claude, Llama3, Titan, RAG, ベクトル検索        |
| EKS/ECS        | カスタム AI/ML 基盤・大規模分散 | Kubeflow, Ray, Triton, KServe, GPU スケジューラ |
| Lambda         | 軽量推論/バッチ推論             | エッジ/リアルタイム API/小型モデル              |
| DynamoDB/S3    | データストア                    | 学習データ/特徴量/モデル/ログ/証跡              |
| Step Functions | MLOps/ワークフロー自動化        | データ前処理 → 学習 → 評価 → デプロイ           |

## 2. AI/ML 基盤設計パターン（ユースケース別）

### 2.1 生成 AI API 基盤（Bedrock）

-   **構成例**:
    -   API Gateway → Lambda/EKS → Bedrock API（Claude 3, Llama3, Titan 等）
    -   ベクトル検索: Bedrock Vector Engine/S3/Opensearch/Pinecone
-   **用途**: チャットボット、要約、RAG、埋め込み生成

### 2.2 モデル学習・デプロイ（SageMaker）

-   **学習**:
    -   SageMaker ノートブック/トレーニングジョブ
    -   データ: S3、特徴量ストア
    -   GPU: ml.p3.2xlarge（1GPU, 61GB RAM, 価格: $3.825/時）
-   **デプロイ**:
    -   SageMaker エンドポイント（推論 API 化）
    -   Auto Scaling: min=1, max=10, target=70%CPU
-   **パイプライン**:
    -   SageMaker Pipelines で学習 → 評価 → デプロイ自動化

### 2.3 カスタム AI/ML 基盤（EKS×Kubeflow）

-   **分散学習**: Kubeflow/PyTorch Lightning/Ray on EKS
-   **推論基盤**: KServe/Triton Inference Server
-   **GPU スケジューリング**:
    -   ノードグループ: p4d.24xlarge（8xA100, 1TB RAM, $32.77/時）
    -   Pod ごとに GPU リソース割当（例: 2GPU/Pod）

## 3. MLOps 設計・パイプライン例

### 3.1 SageMaker Pipelines 例

```python
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import ProcessingStep, TrainingStep, ModelStep

pipeline = Pipeline(
    name="mlops-pipeline",
    steps=[
        ProcessingStep(...),  # 前処理
        TrainingStep(...),    # 学習
        ModelStep(...),       # モデル登録・デプロイ
    ]
)
```

-   **自動化フロー**: S3 データ → 前処理 → 学習 → 評価 → モデル登録 → デプロイ → 監視

### 3.2 Kubeflow Pipelines on EKS

-   YAML/DSL でワークフロー定義
-   例: データ前処理 → 学習 → 評価 → 推論 → 通知

## 4. パフォーマンス・コスト設計（実データ例）

| 項目             | サンプル値                            |
| ---------------- | ------------------------------------- |
| 学習データ量     | 1TB（S3）                             |
| 学習時間         | 2 時間（ml.p3.2xlarge×2 台）          |
| 学習コスト       | $15.3（2 台 ×2 時間 ×$3.825）         |
| 推論レイテンシ   | 120ms（SageMaker エンドポイント p95） |
| ベクトル DB      | 10M ベクトル、検索レイテンシ 50ms     |
| API スループット | 500req/sec（Bedrock 推論 API）        |

## 5. 監視・可観測性・監査

-   **メトリクス**:
    -   学習: CPU/GPU 使用率、学習損失、バッチ処理時間
    -   推論: レイテンシ、エラー率、モデルバージョン
-   **監査証跡**:
    -   SageMaker/Bedrock/EKS の API/操作ログは CloudTrail/S3 に保存
-   **異常検知**:
    -   モデル精度劣化、推論エラー急増、コスト急増時は自動アラート

## 6. セキュリティ・ガバナンス

-   **権限管理**: IAM ロール、SageMaker/EKS の RBAC、Bedrock API キー管理
-   **データ保護**: S3/KMS 暗号化、PrivateLink、VPC エンドポイント
-   **モデル管理**: モデル登録・バージョン管理・リリース承認フロー
-   **法令対応**: 個人情報/機密データの検出・マスキング・監査証跡保存

## 7. 障害対応・Runbook

### 7.1 学習ジョブ失敗

1. CloudWatch/SageMaker Studio でログ確認
2. S3 データ/パラメータ/リソース上限をチェック
3. 必要に応じて再実行・リソース増強
4. 障害記録・再発防止策を Runbook に反映

### 7.2 推論エンドポイント障害

1. CloudWatch でエラー率・レイテンシ急増を検知
2. エンドポイントの再デプロイ/Auto Scaling 設定見直し
3. モデルロールバック・バージョン切替
4. 監査証跡・障害対応履歴を記録

### 7.3 生成 AI API 障害

1. Bedrock API/外部 API のステータス確認
2. API Gateway/Lambda/EKS の疎通・リソース枯渇確認
3. フォールバック/リトライ設計適用

## 8. ベストプラクティス・チェックリスト

-   [ ] 学習・推論基盤は SageMaker/Bedrock/EKS で要件に応じて使い分け
-   [ ] MLOps パイプラインでデータ → 学習 → 評価 → デプロイ → 監視を自動化
-   [ ] モデル・データ・操作ログは必ず監査証跡化し長期保存
-   [ ] コスト・パフォーマンス・精度は定期レビュー
-   [ ] セキュリティ・法令対応・ガバナンスを徹底

## 9. 参考リンク

-   [AWS SageMaker 公式](https://docs.aws.amazon.com/ja_jp/sagemaker/latest/dg/whatis.html)
-   [AWS Bedrock 公式](https://docs.aws.amazon.com/ja_jp/bedrock/latest/userguide/what-is-bedrock.html)
-   [Kubeflow 公式](https://www.kubeflow.org/)
-   [AWS AI/ML 運用ベストプラクティス](https://aws.amazon.com/jp/architecture/data-ai-ml/)

**このドキュメントは、AI/ML/生成 AI 基盤設計・運用・監査・障害対応・拡張・Runbook・具体例・コマンド例まで網羅しています。**
