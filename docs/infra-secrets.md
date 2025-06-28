# シークレット管理・設計・運用・拡張・監査 ドキュメント

このドキュメントは、EKS×Kubernetes×AWS 基盤の**Secret 管理（Kubernetes Secret/AWS Secrets Manager/SSM/Sealed Secrets/External Secrets）・設計・運用・ローテーション・監査・障害対応・拡張**を、
**AWS 公式・CNCF・PCI DSS・現場ベストプラクティス・運用現場の制約まで一切省略せず**、
**粒度高く、体系的に、具体例・コマンド・運用 Runbook・監査証跡・CI/CD 連携・異常系/正常系手順まで**記述します[1][2]。

## 0. シークレット管理の全体像・責任分界

-   **AWS 責任共有モデル**
    -   AWS は KMS/Secrets Manager/SSM の基盤セキュリティを管理。
    -   ユーザーは Secret 値の生成・運用・ローテーション・K8s 連携・監査・漏洩/障害時対応の全責任を負う。

## 1. シークレット管理方式と選定指針

### 1.1 管理方式の選択肢

| 管理方式               | 主用途                        | 特徴・メリット                          | 制約・注意点                           |
| ---------------------- | ----------------------------- | --------------------------------------- | -------------------------------------- |
| K8s Secret             | Pod への env/volume 連携      | K8s 標準、即時反映、RBAC 制御           | etcd 暗号化/KMS 必須、ローテーション弱 |
| AWS Secrets Manager    | DB/API キー/証明書/パスワード | KMS 暗号化、ローテーション自動化、監査  | Pod 連携は External Secrets 等必須     |
| AWS SSM ParameterStore | 設定値/トークン/小規模 Secret | KMS 暗号化、階層管理、監査              | 容量制限、Pod 連携は同上               |
| Sealed Secrets         | GitOps 用暗号化 Secret        | Git 管理安全、CI/CD 連携、復号は K8s 内 | SealedSecretController 必須            |
| External Secrets       | AWS Secrets Manager/SSM 連携  | Secret 自動同期、ローテーション即反映   | Operator 運用、監査設計必須            |

### 1.2 管理戦略

-   **本番は AWS Secrets Manager/External Secrets Operator を必須化**
-   **K8s Secret は KMS Envelope Encryption を有効化（etcd 暗号化）**
-   **Secret 値の Git 直書き厳禁。Sealed Secrets/External Secrets で GitOps 安全運用**
-   **ローテーション/障害/漏洩/監査/CI/CD 連携まで全工程を設計**

## 2. シークレット設計・粒度高い具体例

### 2.1 Kubernetes Secret

#### 2.1.1 YAML 例

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: user-service-secret
    namespace: prod
type: Opaque
data:
    DB_USER:
    DB_PASS:
```

#### 2.1.2 運用ポイント

-   **KMS Envelope Encryption 必須（etcd 暗号化）**
-   **RBAC で namespace 単位/Pod 単位でアクセス権限を最小化**
-   **Secret 値は CI/CD で自動生成・自動反映（例: scripts/db-migrate.sh で Secret 更新）**

#### 2.1.3 参照方法

-   **Pod の envFrom/volumeMount で参照**
-   **アプリコードで直接 Secret API 参照も可（Go/Python/Node 公式 SDK）**

### 2.2 AWS Secrets Manager + External Secrets Operator

#### 2.2.1 ExternalSecret YAML 例

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
    name: user-service-secret
    namespace: prod
spec:
    refreshInterval: "1h"
    secretStoreRef:
        name: aws-secretsmanager
        kind: SecretStore
    target:
        name: user-service-secret
        creationPolicy: Owner
    data:
        - secretKey: DB_USER
          remoteRef:
              key: /prod/user-service/db_user
        - secretKey: DB_PASS
          remoteRef:
              key: /prod/user-service/db_pass
```

#### 2.2.2 運用ポイント

-   **Secrets Manager 側でローテーション設定（Lambda/自動）**
-   **External Secrets Operator で K8s Secret へ自動同期**
-   **監査証跡（CloudTrail/Config）で Secret 操作を全記録**
-   **ローテーション即反映、漏洩時も即時切替**

### 2.3 Sealed Secrets（GitOps）

#### 2.3.1 SealedSecret YAML 例

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
    name: user-service-secret
    namespace: prod
spec:
    encryptedData:
        DB_USER: AgB...
        DB_PASS: AgB...
    template:
        type: Opaque
```

#### 2.3.2 運用ポイント

-   **SealedSecretController をクラスタに必ずデプロイ**
-   **暗号鍵のバックアップ（DR/復旧用）**
-   **Git には暗号化済み SealedSecret のみコミット**

## 3. シークレット運用・CI/CD・監査・ローテーション

### 3.1 CI/CD 連携

-   **Secret 値生成/更新は scripts/db-migrate.sh 等で自動化**
-   **PR 時に Secret 値の変更/生成/削除も CI で検証（Checkov/OPA/独自スクリプト）**
-   **ArgoCD/Flux 等の GitOps ツールで SealedSecret/ExternalSecret も自動反映**

### 3.2 監査証跡・コンプライアンス

-   **CloudTrail/Config で Secrets Manager/SSM の全操作を記録**
-   **K8s Audit Policy で Secret 操作（create/update/delete）を監査**
-   **SealedSecret/ExternalSecret の変更は PR レビュー＋ CI 静的解析必須**

## 4. 正常系・異常系運用 Runbook

### 4.1 正常系（新規追加・更新）

1. **Secret 値生成（例: pwgen/openssl/random）**
2. **Secrets Manager/SSM/SealedSecret に登録**
3. **ExternalSecret/SealedSecret を apply**
4. **Pod 再起動/ローリングアップデートで Secret 値反映**
5. **`kubectl get secret`/`kubectl describe secret`/`kubectl logs`で反映確認**

### 4.2 異常系（漏洩/同期失敗/障害時）

#### 4.2.1 漏洩・不正アクセス

1. **CloudTrail/Config/K8s Audit でアクセス証跡を即時確認**
2. **Secrets Manager/SSM の該当 Secret を即時ローテーション**
3. **ExternalSecret/SealedSecret で新値を K8s に即時反映**
4. **Pod 再起動/ローリングアップデートで新値反映**
5. **影響範囲を全監査証跡で分析し、必要なら IAM/SG/Pod も隔離**

#### 4.2.2 External Secrets/Sealed Secrets 同期失敗

1. **Operator ログ/イベントでエラー詳細確認**
2. **SecretStore/アクセス権/IAM ロール/ネットワーク疎通を確認**
3. **再同期/再 apply/Pod 再起動で復旧**
4. **復旧後は必ず監査証跡・影響範囲を記録**

#### 4.2.3 KMS/etcd 暗号化障害

1. **KMS キーの有効性/アクセス権限を即時確認**
2. **etcd バックアップ/リストア Runbook に従い復旧**
3. **重大障害時は AWS サポート/クラウド管理者へ即時連絡**

## 5. ベストプラクティス・拡張・チェックリスト

-   [ ] Secret 値は絶対に Git/CI/CD ログ/Slack 等に平文で出さない
-   [ ] 本番は Secrets Manager/External Secrets Operator 必須
-   [ ] K8s Secret は KMS Envelope Encryption 必須
-   [ ] Secret のローテーション/監査証跡/復旧 Runbook は必ず明文化・定期訓練
-   [ ] SealedSecret/ExternalSecret は暗号鍵バックアップ・DR 設計も必須
-   [ ] 監査証跡は CloudTrail/Config/K8s Audit で一元管理・定期レビュー

## 6. 参考リンク・外部標準

-   [AWS Secrets Manager 公式](https://docs.aws.amazon.com/ja_jp/secretsmanager/latest/userguide/intro.html)
-   [Kubernetes Secret 公式](https://kubernetes.io/ja/docs/concepts/configuration/secret/)
-   [External Secrets Operator 公式](https://external-secrets.io/v0.9.13/)
-   [Sealed Secrets 公式](https://github.com/bitnami-labs/sealed-secrets)
-   [AWS KMS Envelope Encryption 公式](https://docs.aws.amazon.com/ja_jp/kms/latest/developerguide/concepts.html#envelope-encryption)

**このドキュメントは、Secret 管理の全設計・運用・拡張・監査・障害対応・CI/CD・公式制約・ベストプラクティス・Runbook・具体例まで一切省略せず網羅しています。**

[1] projects.requirement_management
[2] preferences.communication
