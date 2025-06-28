# ユーザー管理・認証・認可・ID 管理・SSO・OIDC・Cognito・IAM 連携 詳細ドキュメント＆Runbook

このドキュメントは、**AWS×EKS×Kubernetes 基盤のユーザー管理・認証・認可・ID 管理・SSO・OIDC・Cognito・IAM 連携**を、
**現場最高水準・網羅性・具体例・数値・段階基準・コマンド例・運用フロー・Runbook**を一切省略せず記述します。

## 0. ユーザー管理・認証/認可の全体像

-   **目的**
    -   安全・効率的なユーザー管理、アクセス制御、監査、法令対応
-   **主な構成要素**
    -   ID 管理（Cognito, IAM, 外部 IdP）、認証（OIDC, SAML, JWT, MFA）、認可（RBAC/ABAC/最小権限）、SSO、監査

## 1. ユーザー ID 管理・プロビジョニング

### 1.1 ID 設計・一意性

-   **ユーザー ID は UUID またはメールアドレスで一意化**
-   **重複登録不可、削除済み ID は再利用禁止（監査要件）**

### 1.2 プロビジョニング方式（段階例）

| 方式      | 適用例・規模感               | 境界値・判断基準                 |
| --------- | ---------------------------- | -------------------------------- |
| 手動登録  | 管理者 UI/CLI で 1 ～ 100 人 | 小規模/PoC/緊急時                |
| CSV 一括  | 100 ～ 1,000 人              | 中規模・定期バッチ               |
| SCIM 自動 | 1,000 人以上/大規模          | SSO/AD 連携/自動同期が必須な場合 |

## 2. 認証方式・強度（境界値・段階基準）

### 2.1 パスワード認証

-   **最低 8 文字、英大文字・小文字・数字・記号を各 1 文字以上必須**
-   **パスワード有効期限: 90 日（PCI DSS/ISMS 推奨）**
-   **連続 5 回認証失敗でアカウントロック（10 分間）**

### 2.2 多要素認証（MFA）

| MFA 方式     | 適用推奨ユーザー規模 | 境界値・判断基準                |
| ------------ | -------------------- | ------------------------------- |
| 任意（推奨） | 1 人～ 100 人        | セキュリティ要件低～中          |
| 強制（必須） | 100 人～             | 管理者/開発者/特権/法令要件あり |

-   **Cognito/Okta/AD 等で TOTP/SMS/Push 通知対応**

### 2.3 SSO/OIDC/SAML

-   **SSO 導入推奨規模: 100 人以上 or 複数 SaaS 連携時**
-   **IdP 例: AWS Cognito, Azure AD, Okta, Google Workspace**
-   **OIDC トークン有効期限: 5 分～ 1 時間（推奨: 15 分）**
-   **SAML アサーション有効期限: 5 分～ 8 時間（推奨: 1 時間）**

## 3. 認可方式・アクセス制御（RBAC/ABAC/最小権限）

### 3.1 ロール設計・粒度

| ロール名     | 権限例               | 適用境界値・判断基準          |
| ------------ | -------------------- | ----------------------------- |
| 管理者       | 全権限               | 1 ～ 5 人（最小限、監査必須） |
| 開発者       | 本番以外の操作・参照 | 10 ～ 100 人                  |
| 一般ユーザー | 自分のデータのみ     | 100 人～                      |
| ゲスト/外部  | 閲覧のみ/一時利用    | 必要に応じて                  |

-   **RBAC/ABAC は Kubernetes/IAM/アプリで一貫性を持たせる**
-   **最小権限原則を徹底し、不要な権限は即時剥奪**

## 4. AWS Cognito 設計・運用（数値・段階例）

### 4.1 ユーザープール設計

-   **最大ユーザー数: 5,000,000 人/プール（公式上限）**
-   **API レートリミット: 50req/sec/アカウント（デフォルト）、申請で引き上げ可**
-   **カスタム属性: 最大 50 個/ユーザー**

### 4.2 Federation/外部 IdP 連携

-   **Google/Apple/LINE/AD/Okta 等と OIDC/SAML 連携**
-   **SSO 連携時は SCIM で自動プロビジョニング推奨**

## 5. IAM 連携・Kubernetes RBAC

### 5.1 IAM ロール設計

-   **IAM ユーザー直接発行は原則禁止、ロール Assume（STS）推奨**
-   **Kubernetes は IRSA/IAM for ServiceAccount で最小権限設計**
-   **例: S3 読み取り専用ロール、DynamoDB 書き込み専用ロール**

### 5.2 RBAC 例（Kubernetes）

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
    namespace: dev
    name: dev-reader
rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["get", "list"]
```

## 6. 監査・運用・障害対応 Runbook

### 6.1 監査証跡

-   **Cognito/IAM/認証認可操作は CloudTrail/S3 に 90 日以上保存**
-   **認証失敗/ロック/権限変更は即時アラート通知**

### 6.2 障害対応・運用 Runbook

1. **認証失敗急増時（5 分間で 10%以上）**
    - CloudWatch/SIEM で検知 → アカウントロック/パスワードリセット
2. **権限誤付与時**
    - IAM/Cognito/アプリの権限を即時ロールバック
3. **SSO 連携障害時**
    - IdP/ネットワーク疎通・証明書有効期限確認 → 手動認証に一時切替

## 7. ベストプラクティス・チェックリスト

-   [ ] パスワード/MFA/SSO は規模・リスク・法令で段階設計
-   [ ] RBAC/ABAC/最小権限を全サービスで徹底
-   [ ] 監査証跡・操作ログは長期保存・定期監査
-   [ ] 障害 Runbook は境界値・閾値ごとに分岐明記
-   [ ] 外部 IdP 連携・フェデレーションは必ず検証・監査

## 8. 参考リンク

-   [AWS Cognito 公式](https://docs.aws.amazon.com/ja_jp/cognito/latest/developerguide/cognito-user-identity-pools.html)
-   [AWS IAM ベストプラクティス](https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/best-practices.html)
-   [Kubernetes RBAC 公式](https://kubernetes.io/ja/docs/reference/access-authn-authz/rbac/)
-   [SCIM 公式仕様](https://tools.ietf.org/html/rfc7644)

**このドキュメントは、ユーザー管理・認証・認可・ID 管理・SSO・OIDC・Cognito・IAM 連携・監査・障害対応・Runbook・具体例・数値・段階基準まで網羅しています。**

[1] https://www.imagazine.co.jp/microservice-architecture/
[2] https://www.cloudsecurityalliance.jp/site/wp-content/uploads/2020/11/best-practices-in-implementing-a-secure-microservices-architecture-J.pdf
[3] https://www.f5.com/ja_jp/company/blog/nginx/best-practices-for-configuring-microservices-apps
[4] https://atmarkit.itmedia.co.jp/ait/articles/2409/06/news069.html
[5] https://ops-in.com/blog/%E3%83%9E%E3%82%A4%E3%82%AF%E3%83%AD%E3%82%B5%E3%83%BC%E3%83%93%E3%82%B9%E3%82%A2%E3%83%BC%E3%82%AD%E3%83%86%E3%82%AF%E3%83%81%E3%83%A3%E3%81%AE6%E3%81%A4%E3%81%AE%E5%B0%8E%E5%85%A5%E6%96%B9%E6%B3%95/
[6] https://jp.tdsynnex.com/blog/cloud/microservice-best-practices/
[7] https://zenn.dev/joaan/articles/e01f8d1bdc3dd6
[8] https://learn.microsoft.com/ja-jp/azure/architecture/guide/architecture-styles/microservices
[9] preferences.quality_assurance
[10] preferences.document_format
[11] preferences.information_presentation
[12] preferences.collaborative_development
[13] preferences.quality_standards
