# Kubernetes マニフェスト運用・設計・拡張・運用手順 ドキュメント

このドキュメントは、EKS×Istio× マイクロサービス基盤の**Kubernetes マニフェスト（Deployment/Service/Ingress/HPA/PDB/Secret/Job/CronJob/CRD 等）運用・設計・拡張・監査・障害対応**を、
**AWS 公式・CNCF・現場ベストプラクティスに基づき、一切省略せず**記述します。

## 1. ディレクトリ・マニフェスト設計

### 1.1 ディレクトリ構成

```
infra/k8s/
  ├── user-service/
  │    ├── deployment.yaml
  │    ├── service.yaml
  │    ├── ingress.yaml
  │    ├── hpa.yaml
  │    ├── pdb.yaml
  │    └── secret.yaml
  ├── video-service/
  ├── chat-service/
  ├── istio/
  │    ├── gateway.yaml
  │    ├── virtualservice.yaml
  │    ├── destinationrule.yaml
  │    ├── authorizationpolicy.yaml
  │    └── requestauthentication.yaml
  ├── db/
  │    ├── rds-operator.yaml
  │    └── secret.yaml
  ├── monitoring/
  │    ├── prometheus.yaml
  │    ├── grafana.yaml
  │    ├── kiali.yaml
  │    └── cloudwatch-agent.yaml
  └── batch/
       ├── job.yaml
       └── cronjob.yaml
```

-   **サービス単位で分離**し、各リソースごとに YAML ファイルを分割
-   **マイクロサービス/ミドルウェア/監視/ジョブ/DB/ネットワーク等もディレクトリで分離**

## 2. マニフェスト詳細・粒度高いリソース設計[2][3][4][5][6][7]

### 2.1 Pod/Deployment

-   **Pod**:
    -   最小の実行単位。通常は Deployment 等で管理[2][3][4]。
    -   例:
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
            name: mypod
        spec:
            containers:
                - name: app
                  image: nginx
        ```
-   **Deployment**:
    -   Replica 管理、ロールアウト/ロールバック、Pod の自己修復[2][4][5]。
    -   例:
        ```yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
            name: user-service
        spec:
            replicas: 3
            selector:
                matchLabels:
                    app: user-service
            template:
                metadata:
                    labels:
                        app: user-service
                spec:
                    containers:
                        - name: user-service
                          image: myimage:1.0
                          resources:
                              requests:
                                  cpu: 200m
                                  memory: 256Mi
                              limits:
                                  cpu: 1
                                  memory: 512Mi
                          envFrom:
                              - secretRef:
                                    name: user-service-secret
                          livenessProbe:
                              httpGet:
                                  path: /health
                                  port: 8080
                              initialDelaySeconds: 10
                          readinessProbe:
                              httpGet:
                                  path: /ready
                                  port: 8080
                              initialDelaySeconds: 5
        ```

### 2.2 Service

-   **Service**:
    -   Pod セットへのアクセス抽象化。type, selector, ports, sessionAffinity, ClusterIP, ExternalName 等[5]。
    -   例:
        ```yaml
        apiVersion: v1
        kind: Service
        metadata:
            name: user-service
        spec:
            selector:
                app: user-service
            ports:
                - protocol: TCP
                  port: 80
                  targetPort: 8080
            type: ClusterIP
        ```
    -   **type**: ClusterIP/NodePort/LoadBalancer/ExternalName
    -   **sessionAffinity**: クライアント IP/None
    -   **複数ポート/プロトコル**: TCP/UDP/SCTP/HTTP/PROXY

### 2.3 Ingress

-   **Ingress**:
    -   外部公開、ALB/IngressClass/HTTPS/証明書/パスルーティング
    -   例:
        ```yaml
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
            name: user-service-ingress
            annotations:
                alb.ingress.kubernetes.io/scheme: internet-facing
                kubernetes.io/ingress.class: alb
        spec:
            rules:
                - host: user.example.com
                  http:
                      paths:
                          - path: /
                            pathType: Prefix
                            backend:
                                service:
                                    name: user-service
                                    port:
                                        number: 80
        ```

### 2.4 HPA/PDB/Job/CronJob

-   **HPA**:
    -   オートスケール（CPU/メモリ/カスタムメトリクス）
        ```yaml
        apiVersion: autoscaling/v2
        kind: HorizontalPodAutoscaler
        metadata:
            name: user-service-hpa
        spec:
            scaleTargetRef:
                apiVersion: apps/v1
                kind: Deployment
                name: user-service
            minReplicas: 2
            maxReplicas: 10
            metrics:
                - type: Resource
                  resource:
                      name: cpu
                      target:
                          type: Utilization
                          averageUtilization: 60
        ```
-   **PDB**:
    -   PodDisruptionBudget で可用性担保
        ```yaml
        apiVersion: policy/v1
        kind: PodDisruptionBudget
        metadata:
            name: user-service-pdb
        spec:
            minAvailable: 2
            selector:
                matchLabels:
                    app: user-service
        ```
-   **Job/CronJob**:
    -   バッチ/定期処理の管理
        ```yaml
        apiVersion: batch/v1
        kind: Job
        metadata:
            name: batch-job
        spec:
            template:
                spec:
                    containers:
                        - name: batch
                          image: batch-image:latest
                    restartPolicy: Never
            backoffLimit: 3
        ```

### 2.5 Secret/ConfigMap

-   **Secret**:
    -   KMS 暗号化/External Secrets Operator 連携/環境変数連携
        ```yaml
        apiVersion: v1
        kind: Secret
        metadata:
            name: user-service-secret
        type: Opaque
        data:
            DB_USER:
            DB_PASS:
        ```
-   **ConfigMap**:
    -   環境設定/アプリ設定の管理

### 2.6 Istio 関連

-   **Gateway/VirtualService/DestinationRule/AuthorizationPolicy/RequestAuthentication**
    -   サービスメッシュの入口/ルーティング/認証認可/トラフィック制御

## 3. 運用・CI/CD・監査・拡張

### 3.1 運用コマンド例[6][7]

-   **マニフェスト適用/更新/削除**
    ```sh
    kubectl apply -f deployment.yaml
    kubectl apply -f service.yaml
    kubectl delete -f deployment.yaml
    ```
-   **雛形生成/説明**
    ```sh
    kubectl run sample --image=nginx --dry-run=client -o yaml
    kubectl explain deployment.spec.template.spec.containers
    ```
-   **複数リソース同時適用**
    ```sh
    kubectl apply -f all.yaml
    ```
-   **差分確認**
    ```sh
    kubectl diff -f deployment.yaml
    ```
-   **状態監視**
    ```sh
    kubectl get all -n
    kubectl describe pod  -n
    kubectl logs  -n
    ```

### 3.2 CI/CD・静的解析・Admission 制御

-   **kube-linter/Checkov/Polaris で静的解析を CI で自動実行**
-   **OPA/Gatekeeper で Admission 制御（ラベル必須/特権 Pod 禁止等）**
-   **ArgoCD/Flux 等の GitOps ツールで自動デプロイ・監査証跡を確保**

### 3.3 正常系・異常系運用手順

#### 正常系

1. **PR 作成 →CI 静的解析・Admission 制御 →main マージ →ArgoCD 自動デプロイ**
2. **`kubectl rollout status deployment/ -n `でロールアウト確認**
3. **`kubectl get hpa`/`kubectl get pdb`でスケール・可用性確認**
4. **Job/CronJob の完了確認は`kubectl get jobs`/`kubectl get cronjobs`/`kubectl logs`**

#### 異常系

-   **デプロイ失敗/Pod 起動失敗**
    -   `kubectl describe pod`/`kubectl logs`で詳細調査 → 設定修正 → 再 apply
    -   必要なら`kubectl rollout undo deployment/ -n `でロールバック
-   **Secret/ConfigMap/External Secret 同期失敗**
    -   Operator ログ/イベント確認 → 再同期・再 apply
-   **リソース競合/削除事故**
    -   `kubectl apply -f `で再作成
    -   ResourcePolicy: keep で削除防止
-   **HPA/PDB 異常**
    -   `kubectl describe hpa`でスケール状況確認、Resource 不足時は LimitRange/ResourceQuota 見直し

### 3.4 監査・セキュリティ・コンプライアンス

-   **全マニフェスト変更は PR レビュー＋ CI 静的解析＋ Admission 制御**
-   **ArgoCD/Flux の Audit ログでデプロイ履歴・差分・操作証跡を保存**
-   **重要リソース（Secret/ServiceAccount/Role 等）は変更時に Slack/メール/JIRA で自動通知**
-   **K8s Audit Policy/CloudTrail で全操作を監査証跡として保存**

## 4. 高可用性・拡張・ベストプラクティス[1][2][4][7]

-   **Deployment は replicas>1、PDB/HPA/ResourceQuota/LimitRange を必ず設定**
-   **Service/Ingress はラベル・セレクタの整合性を厳守**
-   **PodSecurityContext/PodSecurityAdmission で restricted 強制**
-   **Namespace/RBAC で権限分離、Role/RoleBinding/ServiceAccount を明示**
-   **Job/CronJob は backoffLimit/ttlSecondsAfterFinished で管理**
-   **ConfigMap/Secret は環境ごとに分離、External Secrets 推奨**
-   **マニフェストは---区切りで複数リソース同時管理可**
-   **kubectl apply は idempotent、差分管理・再現性を担保**

## 5. 拡張・運用時のチェックリスト

-   [ ] 新サービス追加時はディレクトリ・マニフェスト・RBAC/Quota/Policy も分離
-   [ ] マニフェスト変更時は stg でテストし本番適用
-   [ ] 監査証跡・Admission 制御・CI/CD 連携は必ず維持
-   [ ] 重大障害時の復旧 Runbook は docs/operations.md に記載・随時更新

## 6. 参考・外部リンク

-   [Kubernetes 公式リファレンス](https://kubernetes.io/ja/docs/reference/)[7]
-   [Kubernetes マニフェスト設計ベストプラクティス][1][2][4][5][6]
-   [kubectl explain/--dry-run/--output][6]
-   [CNCF Kubernetes Docs](https://github.com/kubernetes/website)

**このドキュメントは、リソースごとの詳細・運用手順・CI/CD・監査・拡張・障害対応・コマンド例を含み、高水準の Kubernetes マニフェスト運用実現を目指しています。**

[1] https://www.rworks.jp/cloud/kubernetes-op-support/kubernetes-column/kubernetes-entry/30508/
[2] https://itstudy365.com/blog/2025/05/16/kubernetes-learning-%E7%AC%AC12%E7%AB%A0%EF%BC%9A%E3%83%AA%E3%82%BD%E3%83%BC%E3%82%B9%E6%AF%8E%E3%81%AE%E3%83%9E%E3%83%8B%E3%83%95%E3%82%A7%E3%82%B9%E3%83%88%E4%BD%9C%E6%88%90-%E3%80%9Ckubernetes/
[3] https://kubernetes.io/ja/docs/concepts/workloads/pods/
[4] https://qiita.com/tadashiro_ninomiya/items/6e6fea807b2a16732b5b
[5] https://zenn.dev/suiudou/articles/c2aec867000668
[6] https://tanakakns.github.io/kubernetes/manifest/
[7] https://kubernetes.io/ja/docs/reference/
[8] https://sysdig.jp/blog/kubernetes-1-27-whats-new/
