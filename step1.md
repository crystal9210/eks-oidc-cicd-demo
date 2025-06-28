# AWS EKS × Istio × nginx POC 構築手順書（完全版・サンプル情報マスク済み）

このドキュメントは、AWS EKS クラスタ上に Istio を導入し、nginx アプリを外部公開するまでの**全手順**を、**実際のコマンド例や出力例も含めて一切省略せず**、初心者にも分かるように解説したものです。
個人情報や実際のアクセス情報はダミー値やマスクで記載しています。

---

## 目次

1. 前提・準備
2. EKS クラスタの作成
3. Istio のインストール
4. アプリ（nginx）のデプロイ
5. Istio Gateway/VirtualService の設定
6. 外部アクセスの確認
7. AWS コンソールでのリソース確認
8. 各コマンド・出力の詳細解説

---

## 1. 前提・準備

-   Mac OS（zsh）
-   Homebrew で以下をインストール済み
    `awscli`, `kubectl`, `eksctl`, `istioctl`, `helm`
-   AWS アカウント、IAM ユーザーの認証情報設定済み（`aws configure`）
-   AWS リージョン: ap-northeast-1（東京）

---

## 2. EKS クラスタの作成

### コマンド

```

eksctl create cluster --name prod --region ap-northeast-1 --nodes 3 --managed

```

### 実際の出力（一部抜粋・マスク済み）

```

2025-06-29 04:18:32 [ℹ] eksctl version 0.210.0
2025-06-29 04:18:32 [ℹ] using region ap-northeast-1
...
2025-06-29 04:33:05 [✔] all EKS cluster resources for "prod" have been created
2025-06-29 04:33:05 [ℹ] nodegroup "ng-xxxxxxx" has 3 node(s)
2025-06-29 04:33:05 [ℹ] node "ip-192-168-xx-xxx.ap-northeast-1.compute.internal" is ready
2025-06-29 04:33:06 [✔] EKS cluster "prod" in "ap-northeast-1" region is ready

```

#### 解説

-   EKS クラスタとノード（EC2 インスタンス）が自動作成されます。
-   完了まで 10 ～ 20 分かかる場合があります。

---

## 3. Istio のインストール

### コマンド

```

istioctl install --set profile=demo -y

```

### 実際の出力

```

✔ Istio core installed ⛵️
✔ Istiod installed 🧠
✔ Egress gateways installed 🛫
✔ Ingress gateways installed 🛬
✔ Installation complete

```

### バージョン・Pod 確認

```

istioctl version
kubectl get pods -n istio-system

```

出力例：

```

client version: 1.26.2
control plane version: 1.26.2
data plane version: 1.26.2 (2 proxies)
NAME READY STATUS RESTARTS AGE
istio-egressgateway-xxxxxxx 1/1 Running 0 24s
istio-ingressgateway-xxxxxxx 1/1 Running 0 24s
istiod-xxxxxxx 1/1 Running 0 36s

```

-   `istiod`：Istio の司令塔
-   `istio-ingressgateway`：外部からの入口
-   `istio-egressgateway`：外部への出口

---

## 4. アプリ（nginx）のデプロイ

### namespace 作成 & Istio 自動注入有効化

```

kubectl create namespace prod
kubectl label namespace prod istio-injection=enabled

```

出力例：

```

namespace/prod created
namespace/prod labeled

```

### nginx デプロイ & サービス作成

```

kubectl -n prod apply -f https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/application/deployment.yaml
kubectl -n prod expose deployment nginx-deployment --port=80 --type=ClusterIP

```

出力例：

```

deployment.apps/nginx-deployment created
service/nginx-deployment exposed

```

### Pod・Service 確認

```

kubectl -n prod get pods
kubectl -n prod get svc

```

出力例：

```

NAME READY STATUS RESTARTS AGE
nginx-deployment-xxxxxxx-xxxxx 2/2 Running 0 11s
nginx-deployment-xxxxxxx-xxxxx 2/2 Running 0 11s

NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S) AGE
nginx-deployment ClusterIP 10.100.xxx.xxx 80/TCP 11s

```

#### 解説

-   READY が 2/2：nginx 本体＋ Istio サイドカーが両方正常
-   ClusterIP：クラスタ内部向けのサービス

---

## 5. Istio Gateway/VirtualService の設定

### `k8s/gateway.yaml`

```

apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
name: nginx-gateway
namespace: prod
spec:
selector:
istio: ingressgateway
servers:

-   port:
    number: 80
    name: http
    protocol: HTTP
    hosts:
    -   "\*"

```

### `k8s/virtualservice.yaml`

```

apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
name: nginx-vs
namespace: prod
spec:
hosts:

-   "\*"
    gateways:
-   nginx-gateway
    http:
-   route:
    -   destination:
        host: nginx-deployment
        port:
        number: 80

```

### 適用コマンド

```

kubectl apply -f k8s/gateway.yaml
kubectl apply -f k8s/virtualservice.yaml

```

出力例：

```

gateway.networking.istio.io/nginx-gateway created
virtualservice.networking.istio.io/nginx-vs created

```

#### 解説

-   Gateway：外部からの HTTP 通信を受け付ける
-   VirtualService：受け付けた通信を nginx にルーティング

---

## 6. 外部アクセスの確認

### Istio Ingress Gateway の EXTERNAL-IP 確認

```

kubectl -n istio-system get svc istio-ingressgateway

```

出力例（マスク済み）：

```

NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S) AGE
istio-ingressgateway LoadBalancer 10.100.xxx.xxx xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.elb.amazonaws.com 80:xxxxx/TCP,443:xxxxx/TCP 7m6s

```

-   **EXTERNAL-IP**（ALB の DNS 名）が外部アクセス用 URL

### curl またはブラウザでアクセス

```

curl http://xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.elb.amazonaws.com

```

出力例（HTML）：

```

Welcome to nginx!
...
Welcome to nginx!
...

```

#### 解説

-   この HTML が返れば、**外部から nginx アプリにアクセスできている**証拠

---

## 7. AWS コンソールでのリソース確認

### ELB（ロードバランサ）

-   [AWS コンソール > EC2 > ロードバランサー](https://console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#LoadBalancers:)
    -   EXTERNAL-IP と同じ DNS 名の ALB が作成されている

### EKS クラスタ

-   [AWS コンソール > EKS > クラスター > prod](https://console.aws.amazon.com/eks/home?region=ap-northeast-1#/clusters)
    -   「ワークロード」タブで Pod や Service を確認可能
    -   ただし、Kubernetes リソースの詳細は IAM/RBAC 設定によっては見られないこともある

---

## 8. 各コマンド・出力の詳細解説

### 主要なコマンドとその意味

-   `kubectl get nodes`
    → クラスタ内のサーバ（ノード）の状態を確認
-   `istioctl install`
    → Istio のインストール
-   `kubectl get pods -n istio-system`
    → Istio の管理系 Pod が正常か確認
-   `kubectl create namespace ...`
    → 区画（namespace）を作成
-   `kubectl label namespace ... istio-injection=enabled`
    → アプリ Pod に自動で Istio サイドカーを注入
-   `kubectl -n prod apply -f ...`
    → prod namespace にアプリをデプロイ
-   `kubectl -n prod get pods`
    → nginx アプリの Pod が正常か確認
-   `kubectl -n prod get svc`
    → nginx アプリのサービス（内部公開状態）を確認
-   `kubectl -n istio-system get svc istio-ingressgateway`
    → 外部公開用のロードバランサ（ALB）の DNS 名を確認
-   `curl http://`
    → 外部から nginx アプリにアクセス

---

## 参考：ディレクトリ構成例

```

eks-oidc-cicd-demo/
├── k8s/
│ ├── gateway.yaml
│ └── virtualservice.yaml

```

---

## 補足

-   さらに可視化したい場合は Kiali や Grafana の導入もおすすめです（必要に応じて手順追加可能）
-   本番用途では HTTPS 化や認可・認証、mTLS 等の追加設定もご検討ください

---

**NOTES: この md ファイルをもとに、誰でも同じ POC 環境を再現できます。**
