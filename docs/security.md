# 脅威モデル・制御・運用 Doc

## 0. セキュリティ設計の前提と責任共有

-   **AWS 責任共有モデル**を明記：
    -   AWS は EKS コントロールプレーンや物理インフラのセキュリティを担当。
    -   ユーザーは「クラウドの中」（IAM、K8s RBAC、Pod/ノード/ネットワーク/Secret/CI/CD/監査/アプリ脆弱性）の全責任を負う[1][6]。

## 1. 脅威モデルごとの対策・制御・運用

### 1.1 クラスタ/ノード乗っ取り

-   **脅威**:
    -   ノードへの不正アクセス、Pod からノード権限奪取、K8s API サーバーへの攻撃
-   **対策**:
    -   EKS API エンドポイントは**private**化し、必要な IP/SG だけ許可[6]。
    -   ノードは**Private Subnet**に配置。Public IP 割当は原則禁止[5]。
    -   ノード IAM ロールは最小権限、Pod には IRSA（IAM Role for Service Account）で限定権限のみ[5]。
    -   PodSecurityAdmission で**restricted**モード（特権禁止・root 禁止・hostPath 禁止・readOnlyRootFS 強制）[1][6]。
    -   ノード/Pod の脆弱性は**trivy/kube-bench**で CI/CD・定期スキャン[4][5]。
-   **運用・制御**:
    -   ノードグループごとに SG を分離。ノードの SSH は全廃、SSM 経由のみ許可。
    -   ノード障害時は自動再作成、Pod は PDB/HPA で自動再配置。

### 1.2 Pod 間・サービス間の不正通信・横展開

-   **脅威**:
    -   サービス間での不正アクセス、ラテラルムーブメント
-   **対策**:
    -   **NetworkPolicy**で default-deny、必要な通信のみ PodSelector/NamespaceSelector で許可[1][5]。
    -   **Istio mTLS STRICT**を全 Pod 間通信に強制。証明書ローテーション自動化。
    -   **AuthorizationPolicy**で JWT claim や source.principal による通信元制御。
-   **通信阻害リスクと対策**:
    -   mTLS/NetworkPolicy 導入で通信が遮断される場合、**監査ログで通信失敗を検知し、必要な通信のみ明示的に許可**。
    -   CI/CD で通信テスト（E2E）を必ず自動化[2]。

### 1.3 シークレット・認証情報の漏洩

-   **脅威**:
    -   K8s Secret の漏洩、環境変数経由の情報流出、誤った権限付与
-   **対策**:
    -   Secret は**AWS Secrets Manager/SSM**で集中管理し、External Secrets Operator で K8s に同期[5]。
    -   K8s Secret は**KMS Envelope Encryption**で暗号化。アクセス権は namespace 単位で RBAC 制御。
    -   Secret のバージョン管理・ローテーションは自動化、CloudTrail で操作監査。
    -   Secret の値を Pod の環境変数に展開する場合は**最小限のみ**、アプリコードで直接 Secret 参照を推奨[5]。
-   **運用・制御**:
    -   Secret 変更時は監査証跡を必ず記録、誤更新時は即時ロールバック手順を docs/operations.md に明記。

### 1.4 CI/CD・サプライチェーン攻撃

-   **脅威**:
    -   CI/CD パイプラインの乗っ取り、悪意あるイメージ・コードの混入
-   **対策**:
    -   CI/CD 用 IAM は最小権限。ECR プッシュも ArgoCD デプロイも個別に分離[1][5]。
    -   **SBOM（Software Bill of Materials）生成・署名**、Cosign/Notary でイメージ署名・Gatekeeper で署名付きイメージのみ許可。
    -   CI/CD で**trivy/Snyk/kube-linter/kube-bench**を全ジョブで強制[4][5]。
    -   Dependabot/Snyk で依存ライブラリも自動監査。
-   **運用・制御**:
    -   CI/CD 失敗時は即時アラート＋ロールバック。SBOM/署名検証は CI/CD で自動化。

### 1.5 外部公開 API・DDoS/認証バイパス

-   **脅威**:
    -   ALB/API Gateway 経由の攻撃、WAF バイパス、認証バイパス
-   **対策**:
    -   ALB は**WAF 連携**、IP 制限、OIDC 認証を有効化[1][5]。
    -   API は必ず JWT/OIDC 認証＋ Istio で二重認証（RequestAuthentication/AuthorizationPolicy）。
    -   DDoS 対策は AWS Shield/ALB/RateLimit で多層防御。
-   **運用・制御**:
    -   ALB アクセスログは CloudWatch/S3 に保存、異常検知は GuardDuty/SecurityHub でアラート[3][7][8]。

### 1.6 ランタイム脅威/ゼロデイ攻撃

-   **脅威**:
    -   コンテナ実行時の異常動作、マルウェア、ゼロデイ
-   **対策**:
    -   **Amazon GuardDuty Extended Threat Detection**で EKS 監査ログ・ランタイム挙動・API アクティビティを相関監視[3][7][8]。
    -   Falco 等で Pod の異常システムコール・ファイル操作をリアルタイム検知。
-   **運用・制御**:
    -   検知時は自動で Pod 隔離・ノード再作成・Secret ローテーションを Runbook 化[1][3]。

## 2. 制御設計・通信阻害リスクへの配慮

-   **mTLS/NetworkPolicy 導入時は**、
    -   まず stg 環境で全通信パスの E2E テストを自動化
    -   通信失敗時は監査ログ/istio-proxy ログ/NetworkPolicy イベントで即時原因特定
    -   必要な通信のみ明示的に許可。**「許可しすぎ」は絶対にしない**
-   **Istio/OPA/Gatekeeper 導入時は**、
    -   Audit モードでまず違反リソースを検出し、段階的に enforce へ移行
    -   Policy 違反時は CI/CD で Fail ＋ Slack/メール通知
-   **Secret 管理多重化時は**、
    -   Secret 同期遅延やローテーションによる通信断を避けるため、
        -   Secret のバージョン管理・自動ロールバック・監査証跡を必ず設計

## 3. 運用フロー・インシデント対応

-   **インシデント検知 → 影響範囲分析 →Secret ローテーション → 証跡確認 → 復旧 → 事後レビュー**の Runbook を docs/operations.md に明記
-   **CloudTrail/GuardDuty/SecurityHub/K8s Audit Policy/Falco**で全操作・脅威を一元監査
-   **アラートは Prometheus Alertmanager/CloudWatch Alarms/GuardDuty Findings で自動通知＋ JIRA/Slack/Teams 連携**

## 4. コード例・Rego 例・運用例

-   **PodSecurityAdmission（restricted）例**

```yaml
apiVersion: policy/v1
kind: PodSecurityPolicy
metadata:
    name: restricted
spec:
    privileged: false
    allowPrivilegeEscalation: false
    runAsUser:
        rule: "MustRunAsNonRoot"
    fsGroup:
        rule: "MustRunAs"
        ranges:
            - min: 1
              max: 65535
    seLinux:
        rule: "RunAsAny"
    volumes:
        - "configMap"
        - "emptyDir"
        - "projected"
        - "secret"
        - "downwardAPI"
```

-   **Gatekeeper Constraint 例**

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
    name: disallow-privileged
spec:
    match:
        kinds:
            - apiGroups: [""]
              kinds: ["Pod"]
```

-   **trivy/kube-bench/kube-linter CI/CD ジョブ例**（README/CI サンプル参照）

## 5. 参考：AWS 公式ベストプラクティス・運用ガイド

-   [EKS セキュリティベストプラクティス（AWS 公式）][1]
-   [EKS クラスタの保護（AWS 公式）][2]
-   [EKS ベストプラクティスガイド（まとめ）][5]
-   [EKS 脅威検知と GuardDuty][3][7][8]
-   [責任共有モデル][1][6]

[1][2][3][5][6][7][8]

[1] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/security.html
[2] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/security-best-practices.html
[3] https://aws.amazon.com/jp/blogs/news/aws-reinforce-roundup-2025-top-announcements/
[4] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/introduction.html
[5] https://qiita.com/jondodson/items/5d3a586b4759d3db222b
[6] https://dev.classmethod.jp/articles/decipher-amazon-eks-best-practices-guide-for-security-part1/
[7] https://aws.amazon.com/jp/blogs/news/aws-weekly-20250616/
[8] https://ops-today.com/topics-13117/
