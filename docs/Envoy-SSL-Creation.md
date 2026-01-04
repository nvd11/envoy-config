# 为独立 Envoy 代理生成和管理 Google SSL 证书

本文档详细描述了我们如何为一个运行在 GCE 虚拟机上的独立 Envoy 代理，申请 SSL 证书并管理其私钥。

这个方案的核心是，我们需要将最终的证书和私钥文件放置到虚拟机的本地文件系统上，供 Envoy 读取。

## 一、 整体流程

我们采用"云端管理、运行时获取"的最佳实践，整个流程分为两部分：
1.  **一次性设置**：在 Google Cloud 上创建托管资源（DNS授权、证书、私钥）。
2.  **运行时获取**：在虚拟机的启动脚本 (`setup_envoy.sh`) 中，添加指令，让虚拟机在每次启动时，都从云端安全地拉取证书和私钥。

## 二、 一次性设置步骤详解

以下是我们需要执行的、用于创建云端资源的操作。

### 1. 创建 DNS 授权

首先需要为域名创建 DNS 授权，用于验证域名所有权。

-   **创建 DNS 授权**:
    ```bash
    gcloud certificate-manager dns-authorizations create www-jpgcp-auth --domain=www.jpgcp.cloud
    ```

-   **获取 DNS 验证信息**:
    ```bash
    gcloud certificate-manager dns-authorizations describe www-jpgcp-auth --format="table(name,domain,dns_resource_record)"
    ```

-   **在 DNS 提供商处添加记录**:
    根据上一步的输出，在 DNS 提供商处添加相应的 CNAME 记录。例如：
    - **名称**: `_acme-challenge.www.jpgcp.cloud`
    - **类型**: CNAME
    - **值**: `c4b0bc6e-4e65-4d7e-beef-4af2d442e483.6.authorize.certificatemanager.goog`

### 2. 创建 Google Cloud 管理证书

使用 DNS 授权创建受信任的 SSL 证书。

-   **创建证书资源**:
    ```bash
    gcloud certificate-manager certificates create envoy-managed-cert \
      --domains=www.jpgcp.cloud \
      --dns-authorizations=www-jpgcp-auth \
      --scope=all-regions
    ```

-   **等待证书签发**:
    ```bash
    gcloud certificate-manager certificates describe envoy-managed-cert --format="table(name,managed.state)"
    ```
    等待状态从 `PROVISIONING` 变为 `ACTIVE`。

### 3. 将私钥安全地存放到 Secret Manager

私钥是高度敏感的信息，我们使用 Google Secret Manager 来安全地存储它。

-   **生成私钥**:
    ```bash
    openssl genpkey -algorithm RSA -out private.key -pkeyopt rsa_keygen_bits:2048
    ```

-   **创建 Secret 容器**:
    ```bash
    gcloud secrets create envoy-private-key --locations="europe-west2" --replication-policy="user-managed"
    ```
    我们创建了一个名为 `envoy-private-key` 的 Secret 容器。

-   **上传私钥内容**:
    ```bash
    gcloud secrets versions add envoy-private-key --data-file="private.key"
    ```
    我们将本地 `private.key` 文件的内容，作为第一个版本添加到了这个 Secret 中。

## 三、 资源当前存放在哪里？

在完成以上步骤后，我们的证书和私钥的"权威来源"已经位于 Google Cloud 上：

-   **私钥 (Private Key)**: 安全地存储在 **Google Secret Manager** 中，Secret 的名称是 `envoy-private-key`。
-   **公钥证书 (Public Certificate)**: 存放在 **Google Certificate Manager** 中，证书的名称是 `envoy-managed-cert`。

## 四、 运行时获取

我们接下来的计划，就是在虚拟机的启动脚本中，分别从这两个地方拉取内容，并将它们放置到 Envoy 配置所期望的路径：`/etc/ssl/private/envoy/private.key` 和 `/etc/ssl/certs/envoy/cert.pem`。

### 从 Secret Manager 获取私钥
```bash
gcloud secrets versions access latest --secret=envoy-private-key --out-file=/etc/ssl/private/envoy/private.key
```

### 从 Certificate Manager 获取证书
注意：目前 Google Cloud Certificate Manager 没有直接的 export 命令，可能需要通过其他方式获取证书内容，或者使用自签名证书进行测试。

## 五、 PK（私钥）和 CSR（证书签名请求）的关系

### 1. 基本概念
- **私钥 (Private Key, PK)**：您生成的加密密钥，必须严格保密
- **CSR (Certificate Signing Request)**：包含公钥和域名信息的申请文件

### 2. 生成关系
```
私钥 (PK) → 生成 → CSR → 提交给CA → 获得证书
```

### 3. 详细解释
- **私钥生成**：使用 `openssl genpkey` 生成私钥
- **CSR生成**：使用私钥生成CSR，CSR包含：
  - 公钥（从私钥派生）
  - 域名信息（CN=www.jpgcp.cloud）
  - 组织信息（可选）
- **证书签发**：CA使用CSR中的公钥签发证书

### 4. 关键特性
- **一一对应**：每个CSR都与特定的私钥绑定
- **不可逆**：可以从私钥生成CSR，但不能从CSR反推私钥
- **安全机制**：私钥始终在本地，只将CSR（包含公钥）发送给CA

### 5. 验证关系
```bash
# 验证私钥和CSR是否匹配
openssl rsa -in private.key -noout -modulus | openssl md5
openssl req -in cert.csr -noout -modulus | openssl md5
# 如果两个MD5值相同，说明匹配
```

## 六、 注意事项

1. **证书签发时间**：DNS 记录生效后，证书签发通常需要 15-60 分钟。
2. **证书自动续期**：Google Cloud 管理的证书会自动续期。
3. **私钥安全**：私钥必须严格保护，建议存储在 Secret Manager 中。
4. **测试阶段**：在证书签发完成前，可以使用自签名证书进行测试，但浏览器会显示安全警告。
