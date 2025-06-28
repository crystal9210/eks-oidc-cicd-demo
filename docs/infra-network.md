# EKS×Kubernetes ネットワーク設計・運用 ドキュメント

## 0. EKS ネットワーク設計の前提と責任範囲

-   **AWS 責任共有モデル**
    -   EKS コントロールプレーンの ENI/VPC 配置・API サーバーの ENI/SG は AWS 管理。ただし VPC/サブネット/SG/ルート/ACL/Pod ENI/Pod SG/NetworkPolicy/Service Mesh/通信経路の設計・管理はユーザー責任[1][4][6][7]。

## 1. VPC/サブネット設計・運用

### 1.1 CIDR・IPv4/IPv6・サブネット分割

-   **CIDR**: 10.0.0.0/16 等、将来の拡張を考慮し十分なアドレス空間を確保[6]。
-   **IPv4/IPv6**:
    -   デフォルトは IPv4。IPv6 利用時はデュアルスタック VPC/サブネット必須[6]。
-   **サブネット分割**:
    -   Public（ALB/NAT/Bastion）、Private（EKS ノード/Pod）、Isolated（RDS/ElastiCache）[6]。
    -   各 AZ ごとに Public/Private/Isolated サブネットを用意し、Multi-AZ 冗長を徹底。

### 1.2 ENI/X-ENI/Pod ENI 設計

-   **EKS コントロールプレーン ENI/X-ENI**:
    -   クラスタ作成時に指定したサブネットに自動配置。API サーバー通信はこの ENI 経由[6]。
-   **Pod ENI（VPC CNI）**:
    -   Pod ごとに ENI を割り当てる場合、`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`を設定し、ENIConfig CRD でサブネット/SG を Pod 単位で指定可能[2][4]。
    -   サブネットごとに ENIConfig リソースを作成し、Pod のサブネット/SG 分離を実現[2]。

#### ENIConfig 例

```yaml
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
    name: subnet-a
spec:
    securityGroups:
        - sg-xxxxxxxx
    subnet: subnet-xxxxxxxx
```

### 1.3 VPC Peering/Transit Gateway/Hybrid Networking

-   **マルチクラスタ/マルチアカウント/ハイブリッド（オンプレ/エッジ）**:
    -   VPC Peering/Transit Gateway でルーティング。ルートテーブル/SG/ACL で通信範囲を厳密に制御[5]。
    -   ハイブリッドノード・リモートノード CIDR・リモート Pod CIDR 設計とルート追加[5]。
    -   すべてのノード/Pod/コントロールプレーンが L3 で相互到達可能なことが必須[5]。

## 2. セキュリティグループ・ACL・Firewall 設計

### 2.1 SG 設計

-   **ノード SG/Pod SG/ALB SG/RDS SG/管理用 SG**を分離し、最小権限で設計。
-   **Pod Security Group（EKS Pod ENI）**:
    -   Pod 単位で SG を割り当てる場合は Pod ENI と ENIConfig を活用[2][4]。
-   **SG の自動管理**:
    -   EKS クラスタ作成時のクラスタ SG（clusterSecurityGroupId）は API サーバー通信等で自動利用[2]。

### 2.2 Network ACL

-   **VPC 全体の補助的な制御。Public/Private/Isolated ごとにルールを分離**。
-   **監査証跡（Flow Logs）を必ず有効化**。

## 3. Kubernetes NetworkPolicy 設計・運用

### 3.1 基本方針

-   **全 namespace で default-deny（Ingress/Egress 両方）を必ず適用**。
-   **PodSelector/NamespaceSelector で必要な通信のみ許可**。
-   **DNS/Egress to Internet も明示的に許可（必要な場合のみ）**。

### 3.2 NetworkPolicy 例

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
    name: default-deny-all
    namespace: prod
spec:
    podSelector: {}
    policyTypes:
        - Ingress
        - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
    name: allow-alb-to-user-service
    namespace: prod
spec:
    podSelector:
        matchLabels:
            app: user-service
    ingress:
        - from:
              - ipBlock:
                    cidr: 10.0.1.0/24 # ALBサブネット
          ports:
              - protocol: TCP
                port: 80
```

### 3.3 運用・監査

-   **NetworkPolicy 適用/変更時は必ず通信テスト（E2E/監査ログ）を実施**。
-   **NetworkPolicy Viewer 等で可視化・監査**。

## 4. Istio Service Mesh/Ingress/Egress Gateway 設計

### 4.1 Ingress Gateway

-   **ALB→istio-ingressgateway に集約。HTTPS 終端、mTLS、WAF 連携**。
-   **Ingress Gateway は Multi-AZ 配置。HPA/PDB で可用性担保**。

### 4.2 Egress Gateway

-   **外部 API/SaaS/インターネット通信は必ず Egress Gateway 経由**。
-   **監査証跡・トラフィック制御・mTLS/ACM Private CA 連携**。

### 4.3 サービス間通信・マルチクラスタ

-   **Istio mTLS STRICT を全 Pod 間通信に強制**。
-   **VirtualService/DestinationRule でパス/ホスト/バージョンルーティング、リトライ/CB/レートリミット**。
-   **AuthorizationPolicy/RequestAuthentication で通信元・JWT クレーム制御**。
-   **East-West Gateway/ServiceEntry/ExternalName でクラスタ間通信を設計**。
-   **TrustDomain 設計でサービス ID を一意化、なりすまし防止**[5]。

## 5. ハイブリッド/エッジ/IPv6/特殊構成

-   **EKS Hybrid Nodes/オンプレ/エッジノード**
    -   リモートノード CIDR/Pod CIDR 設計、VPC ルート追加、ENI/X-ENI/Pod ENI の配置設計[5]。
    -   すべてのノード/Pod/コントロールプレーンが L3 で相互到達可能であることが必須[5]。
-   **IPv6 デュアルスタック**
    -   VPC/サブネット/Pod/Service/Ingress の IPv6 対応、ルート/SG/NetworkPolicy も IPv6 対応[6]。

## 6. 通信経路・可視化・監査

-   **Kiali でサービスメッシュのトポロジ・トラフィック・異常通信を可視化**。
-   **VPC Flow Logs/CloudTrail で全通信/設定変更を監査証跡として保存**。
-   **K8s Audit Policy で API サーバーの通信・設定変更も記録**。

## 7. 障害対応・運用手順

### 7.1 ネットワーク断/通信不可時

1. **Kiali でトラフィック断点を特定**
2. **ALB/SG/VPC/Route53/NetworkPolicy/Istio Gateway/ENIConfig 設定を確認**
3. **VPC Flow Logs/CloudTrail で通信失敗の証跡を調査**
4. **設定ミス/障害を修正 → 疎通確認**

### 7.2 ハイブリッド/マルチクラスタ通信障害

1. **ServiceEntry/TrustDomain/East-West Gateway/ENIConfig 設定を確認**
2. **VPC Peering/Transit Gateway ルート/SG/リモート CIDR を確認**
3. **Istio の証明書/TrustDomain 不整合も調査**

## 8. 拡張・運用時のチェックリスト

-   [ ] 新クラスタ/サブネット/サービス追加時は CIDR/SG/NetworkPolicy/Istio Gateway/ENIConfig を必ず設計・監査
-   [ ] 監査証跡（Flow Logs/CloudTrail/K8s Audit）は必ず有効化・定期レビュー
-   [ ] IPv6/ハイブリッド/エッジ/マルチクラスタ時はルート/SG/ENI/ENIConfig/Pod CIDR/TrustDomain を再設計
-   [ ] 重大障害時の復旧 Runbook は docs/operations.md に記載・随時更新

## 9. 参考リンク・外部標準

-   [EKS ネットワーク設計公式ガイド][1][4][6]
-   [EKS VPC CNI カスタムネットワーク][2]
-   [EKS Hybrid Nodes ネットワーク][5]
-   [AWS Black Belt EKS][7]
-   [Kubernetes NetworkPolicy 公式]
-   [Istio Service Mesh 設計]
-   [CNCF ネットワークパターン][8]

**このドキュメントは、EKS ネットワークの全設計・運用・拡張・監査・障害対応・ハイブリッド/IPv6/マルチクラスタ/ENI/Pod SG/通信経路/公式制約まで一切省略せず網羅しています。**

[1] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/eks-networking.html
[2] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/cni-custom-network-tutorial.html
[3] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/eks-ug.pdf
[4] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/networking.html
[5] https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/hybrid-nodes-concepts-networking.html
[6] https://docs.aws.amazon.com/ja_jp/eks/latest/best-practices/subnets.html
[7] https://pages.awscloud.com/rs/112-TZM-766/images/AWS-Black-Belt_2024_Amazon-EKS-Introduction_1010_v1.pdf
[8] https://bookplus.nikkei.com/atcl/catalog/25/03/06/01896/
