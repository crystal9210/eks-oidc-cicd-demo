# API GATEWAY 詳細ドキュメント＆Runbook 集

このドキュメントは、**AWS API Gateway（REST/HTTP）×EKS×Kubernetes 基盤**の API 設計・認証認可・スロットリング・外部連携・監査・障害対応・トラブルシューティングを、
**AWS 公式ガイド・現場知見・実データ・エラー判定・Runbook・判断基準**まで一切省略せず、**初心者でも段階的に運用・対応できるよう**体系化しています[9][10][11][12]。

## 0. 設計・運用全体像

-   **API Gateway の役割**
    -   API 公開、認証認可、レート制御、監査、外部連携、障害遮断、WAF・セキュリティ
-   **構成例**
    -   API Gateway（REST/HTTP）→ Lambda/EKS/ECS/Fargate/ALB Ingress

## 1. スロットリング・レートリミット・クォータ設計

| 設定単位           | デフォルト値               | 境界値・段階例           | 備考           |
| ------------------ | -------------------------- | ------------------------ | -------------- |
| アカウント全体     | 10,000RPS/5,000 バースト   | 最大 20,000RPS（申請可） | 主要リージョン |
| ステージ単位       | 任意（例:2,000/1,000）     | アカウント上限内で調整   |                |
| メソッド単位       | 任意（例:100/50）          | ステージ上限内で調整     |                |
| API キー/UsagePlan | 任意（例:500/200/日 1 万） | 利用者・用途ごとに細分化 |                |

-   **本番推奨段階値**
    -   重要 API: 2,000RPS/1,000 バースト
    -   管理 API: 100RPS/50 バースト
    -   外部 API: 500RPS/200 バースト＋ WAF 必須
-   **429 発生時**
    -   直近 1 分間でエラー率>0.5%なら即時アラート・再試行設計

## 2. 認証・認可・IAM 連携

### 2.1 認証パターン・具体例

| 方式        | 境界値・運用例                           | エラー時の挙動・対応        |
| ----------- | ---------------------------------------- | --------------------------- |
| Cognito     | JWT 有効期限:5 分～ 1 時間（推奨 15 分） | 401/403 エラー、再認証促す  |
| API Key     | 1 キー/日 1 万回（例）                   | 403 エラー、キー再発行/通知 |
| IAM 認証    | IAM ロール/ポリシーで操作制御            | 403 エラー、権限再付与      |
| Lambda 認証 | IP/ロール/外部 API 連携                  | 403/401、Lambda ログ確認    |

-   **IAM 権限エラー例**

    ```
    User: arn:aws:iam::123456789012:user/foo is not authorized to perform: apigateway:GetWidget on resource: my-example-widget
    ```

    → IAM ポリシー修正[4]

-   **PassRole エラー**
    ```
    User: arn:aws:iam::123456789012:user/bar is not authorized to perform: iam:PassRole
    ```
    → `iam:PassRole`権限付与[4]

## 3. 監査・可観測性・アクセスログ

-   **CloudWatch Logs/アクセスログ**: 30 日～ 7 年保存（法令・監査要件）
-   **$context 変数でリクエスト各フェーズの詳細を記録**
    -   例：
        ```
        "authenticate-status": "200",
        "authorize-status": "403",
        "integration-status": "-",
        "response-latency": "52",
        "status": "403"
        ```
        → 各フェーズでどこが失敗したかを即判別可能[2]
-   **主要メトリクス**
    -   5XXError, 4XXError, Latency, IntegrationLatency, Count

## 4. トラブルシューティング・障害対応 Runbook

### 4.1 主要エラー別対応（詳細・具体例）

| エラーコード | 主な発生要因                                | 判定・対応フロー                                                                                                    |
| ------------ | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| 401/403      | 認証・認可失敗、API キー不正、IAM 権限不足  | 認証フェーズ（authenticate/authorize）ログ確認、IAM/認証設定/キー有効期限確認、Lambda ログ調査[2][4]                |
| 429          | スロットリング/レート超過                   | レート/バースト/クォータ値を確認、UsagePlan/上限申請・緩和、クライアント側指数バックオフ実装                        |
| 500/502      | バックエンド（Lambda/HTTP）エラー、統合不備 | CloudWatch ログ、$context.integrationErrorMessage 確認、Lambda/統合先のエラーログ・タイムアウト・IAM 権限確認[5][6] |
| 503          | バックエンド過負荷/メンテ/疎通不可          | バックエンドリソース増強、API Gateway のリトライ設計、クライアント側指数バックオフ実装                              |
| 504          | タイムアウト（最大 29 秒）                  | Lambda/統合先の処理時間短縮、API Gateway タイムアウト調整                                                           |
| 5XX（全般）  | バックエンド障害、API Gateway 内部障害      | CloudWatch Logs で詳細調査、AWS サポートへ連携[5][7]                                                                |

#### 500 Internal Server Error 詳細対応（例）

-   **原因候補**
    -   API デプロイ不備、バックエンド例外/タイムアウト、リソース上限超過、IAM 権限不足[5][6][7]
-   **対応手順**
    1. CloudWatch Logs でエラー詳細確認
    2. エラーメッセージ/パターン分析（例：`$context.error.message`で統合エラー内容取得）
    3. API 設定・デプロイ状況確認（ステージ/リソース/統合タイプ）
    4. バックエンドのヘルスチェック・エラーログ・リソース監視
    5. タイムアウト/リソース制限/スロットリング設定を見直し
    6. IAM ロール・ポリシー・PassRole 権限確認
    7. 必要に応じて AWS サポート連携[5][6][7]

## 5. 障害調査・証跡取得のベストプラクティス

-   **アクセスログ・$context 変数で各フェーズのステータス・エラー内容を記録**[2]
-   **CloudWatch Logs Insights で時系列・エラー頻度・特定ユーザー/メソッドの影響範囲を分析**
-   **API Gateway/バックエンド双方のメトリクス・ログを突き合わせて因果関係を特定**
-   **IAM/認証エラーは必ず CloudTrail で操作証跡も確認**

## 6. 主要なトラブル・障害パターンと現場対応例

### 6.1 デプロイ・設定ミス

-   **症状**: 新しいエンドポイントが 404/405/500
-   **対応**: API Gateway のリソース/メソッド/統合設定・デプロイ状況を再確認

### 6.2 バックエンド疎通・ヘルスチェック失敗

-   **症状**: 502/504/503 エラー多発
-   **対応**:
    -   Lambda/HTTP 統合先のエラーログ・ヘルスチェック
    -   タイムアウト/リソース制限/ネットワーク ACL/SG 設定確認

### 6.3 IAM/認証・認可エラー

-   **症状**: 401/403 エラー多発、統合呼び出し不可
-   **対応**:
    -   IAM ロール/ポリシー/PassRole 権限確認
    -   API Gateway→Lambda 統合時は`lambda:InvokeFunction`権限必須[6]

### 6.4 スロットリング・リソース枯渇

-   **症状**: 429 エラー急増、API レスポンス遅延
-   **対応**:
    -   スロットリング/クォータ設定見直し
    -   バックエンドのオートスケール・キャッシュ導入

## 7. 監査・セキュリティ・外部連携

-   **WAF 連携**: SQLi/XSS/Bot 対策は必須
-   **VPC Link/PrivateLink**: 内部 API は VPC 経由でセキュアに公開
-   **API キー/UsagePlan**: 外部連携は必ず API キー＋クォータ制御

## 8. 運用ベストプラクティス・チェックリスト

-   [ ] スロットリング/クォータは本番・用途別に段階設計し 429 発生時は即通知
-   [ ] 認証・認可・IAM 権限は定期的に監査・テスト
-   [ ] 監査証跡・API メトリクスは長期保存し閾値超過時にアラート
-   [ ] 主要エラー（401/403/429/500/502/503/504）は Runbook 化し定期訓練
-   [ ] CloudWatch Logs/$context.integrationErrorMessage で障害証跡を残す

## 9. 参考リンク

-   [API Gateway HTTP API トラブルシューティング（公式）][1]
-   [API Gateway Enhanced Observability Variables（公式）][2]
-   [API Gateway IAM/認証トラブルシューティング（公式）][4]
-   [API Gateway 500/5XX エラー対応（公式）][5][6][7]

**このドキュメントは、API Gateway 設計・運用・障害対応・トラブルシューティング・エラー判定・Runbook・監査・具体例・数値・判断基準まで網羅しています。**

[1] https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-troubleshooting.html
[2] https://aws.amazon.com/blogs/compute/troubleshooting-amazon-api-gateway-with-enhanced-observability-variables/
[3] https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-known-issues.html
[4] https://docs.aws.amazon.com/apigateway/latest/developerguide/security_iam_troubleshoot.html
[5] https://apipark.com/techblog/en/how-to-resolve-the-500-internal-server-error-in-aws-api-gateway-api-calls-a-step-by-step-guide/
[6] https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-troubleshooting-lambda.html
[7] https://repost.aws/knowledge-center/api-gateway-5xx-error
[8] https://stratusgrid.com/blog/exploring-a-universal-troubleshooting-framework
[9] preferences.information_presentation
[10] preferences.instruction_format
[11] preferences.technical_documentation
[12] preferences.feedback_format
