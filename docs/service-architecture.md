# API Gateway 設計・認証認可・スロットリング・外部連携 詳細ドキュメント＆Runbook 集

このドキュメントは、**AWS×EKS×Kubernetes 基盤の API Gateway 設計・運用・認証認可・スロットリング・外部連携・監査・障害対応**を、
**AWS 公式・現場ベストプラクティス・実データ・具体例・コマンド・運用フロー・Runbook・境界値まで一切省略せず記述します**。

## 0. API Gateway 設計の全体像

-   **目的**
    -   マイクロサービス/API の一元公開、認証認可、トラフィック制御、監査、外部連携の安全・効率化
-   **主な選択肢**
    -   AWS API Gateway、ALB Ingress Controller、NGINX Ingress、Kong、Ambassador、Istio IngressGateway

## 1. スロットリング・レートリミット・クォータ（具体値・境界値）

### 1.1 AWS API Gateway のスロットリング設定

API Gateway では、**アカウント全体・ステージ・メソッド・API キー単位**でスロットリング（レートリミット/バースト）とクォータを設定できます[1][2][3][4][5][6][7][8]。

| 設定対象           | レートリミット（RPS） | バースト（同時処理数） | クォータ（例）   | 境界値・段階例                        |
| ------------------ | --------------------- | ---------------------- | ---------------- | ------------------------------------- |
| アカウント全体     | 10,000（デフォルト）  | 5,000（デフォルト）    | -                | 申請で最大 20,000RPS まで引き上げ可能 |
| ステージ単位       | 任意（例: 2,000）     | 任意（例: 1,000）      | -                | アカウント上限を超えない範囲で設定    |
| メソッド単位       | 任意（例: 100）       | 任意（例: 50）         | -                | ステージ上限を超えない範囲で設定      |
| API キー/UsagePlan | 任意（例: 500）       | 任意（例: 200）        | 例: 10,000 回/日 | 利用者・用途ごとに細かく制御          |

-   **デフォルト値（主要リージョン）**:
    -   レートリミット: 10,000 RPS（1 秒あたりリクエスト数）
    -   バースト: 5,000（同時処理リクエスト数）[4]
    -   一部リージョンは 2,500/1,250 等の例外あり[4]
-   **境界値例**:
    -   1 秒間にレート＋バースト（例: 10,000+5,000=15,000）までなら 429 エラーなし
    -   それ以上は**429 Too Many Requests**エラー[5]
    -   例: レート 10/秒, バースト 100 で 1 秒間に 109 リクエスト → 全て処理、110 リクエスト →1 件 429 エラー[5]
-   **クォータ例**:
    -   1 日 10,000 回、1 ヶ月 30 万回、1 分間 1,000 回など、API キー単位で段階設定可能[8]

### 1.2 スロットリング設定例（Terraform）

```hcl
resource "aws_api_gateway_method_settings" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  stage_name  = aws_api_gateway_stage.example.stage_name
  method_path = "*/*"
  settings {
    throttling_rate_limit  = 1000   # 1秒あたりの最大リクエスト数
    throttling_burst_limit = 500    # バースト時の最大同時リクエスト数
  }
}
```

-   **推奨段階値**:
    -   開発環境: 50–200 RPS、バースト 50–100
    -   本番: 1,000–10,000 RPS、バースト 500–5,000（要負荷試験で決定）

## 2. 認証・認可設計（OIDC/JWT/Cognito/API Key）

### 2.1 認証方式別の具体例

| 認証方式          | 適用例・境界値                            | 備考                     |
| ----------------- | ----------------------------------------- | ------------------------ |
| Cognito 連携      | JWT 有効期限: 5 分～ 1 時間、最大 24 時間 | 失効後は再認証必須       |
| API Key           | 1 キーあたり 1 日 1 万回まで（例）        | UsagePlan で段階設定可能 |
| Lambda Authorizer | IP 制限: 10.0.0.0/8, 192.168.0.0/16 等    | 複数条件組み合わせ可能   |

## 3. スロットリング・WAF・レートリミットの実運用境界値

-   **スロットリング境界値の設計例（本番）**
    -   API 全体: 10,000 RPS/5,000 バースト（デフォルト最大）
    -   重要 API: 2,000 RPS/1,000 バースト
    -   管理 API: 100 RPS/50 バースト
    -   外部公開 API: 500 RPS/200 バースト＋ WAF 必須
-   **WAF ルール例**
    -   SQLi/XSS: デフォルト有効
    -   IP 制限: 会社 IP のみ許可/海外 IP ブロック
    -   Bot 対策: 1 分間 100 回超は自動ブロック

## 4. 外部連携・バックエンド統合（具体例）

-   **API Gateway→Lambda**: 1 リクエストあたりタイムアウト 30 秒、ペイロード最大 6MB
-   **API Gateway→EKS Ingress**: ALB 経由で最大 10,000RPS までスケール
-   **VPC Link/PrivateLink**: 内部 API は VPC 経由で公開、外部からは直接アクセス不可

## 5. 監査・可観測性・運用（数値例）

-   **アクセスログ**: S3/CloudWatch に 30 日保存（法令要件により 90 日～ 7 年も）
-   **API メトリクス例（直近 24 時間）**
    -   平均レイテンシ: 120ms（p95: 220ms）
    -   エラー率: 0.02%
    -   スループット: 3,500req/sec（ピーク時: 8,900req/sec）

## 6. 障害対応・Runbook（境界値付き）

### 6.1 429/503 エラー多発時

1. **CloudWatch でエラー率>0.5%を検知した場合**
2. **API Gateway/Ingress/Istio のスロットリング/バースト値を確認**
    - 例: レート 1,000/バースト 500 で 1,600 リクエスト →100 件 429 エラー
3. **必要に応じて上限拡張 or クライアント側リトライ設計を適用**

### 6.2 認証エラー急増時

1. **JWT 有効期限切れユーザーが 10%以上検知された場合**
2. **Cognito/Authorizer の設定・API キー有効期限を確認**

## 7. ベストプラクティス・チェックリスト

-   [ ] スロットリングは本番・用途別に段階値を設計し、429 発生時は即時検知・通知
-   [ ] API Key/UsagePlan で利用者ごとにクォータ・上限を細分化
-   [ ] WAF/IP 制限/認証方式はリスク・用途ごとに段階設計
-   [ ] 監査証跡・API メトリクスは長期保存し、閾値超過時はアラート
-   [ ] 障害 Runbook は境界値・閾値ごとに分岐を明記

## 8. 参考リンク

-   [Amazon API Gateway のクォータ（公式）][4]
-   [API Gateway のスロットリング設定（公式）][1][3]
-   [API Gateway のスロットリング検証記事][2][5][6][7][8]

**このドキュメントは、API Gateway 設計・認証認可・スロットリング・外部連携・監査・障害対応・Runbook・具体値・境界値・段階設計まで網羅しています。**

[1] https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/api-gateway-request-throttling.html

[2] https://dev.classmethod.jp/articles/apigateway-throttling-test/

[3] https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/http-api-throttling.html

[4] https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/limits.html

[5] https://repost.aws/ja/questions/QUfzOnWBHzQ0SAPJw0tWqopQ/api-gateway-%E3%81%AE%E3%82%B9%E3%83%AD%E3%83%83%E3%83%88%E3%83%AA%E3%83%B3%E3%82%B0%E3%81%AE%E6%8C%99%E5%8B%95%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6%E8%B3%AA%E5%95%8F%E3%81%A7%E3%81%99%E3%80%82

[6] https://sogo.dev/posts/2023/02/aws-api-gateway-terraform-throttling-settings

[7] https://zenn.dev/tomomik210/articles/90851eb551b00f

[8] https://dev.classmethod.jp/articles/api-gateway-usage-plan/
