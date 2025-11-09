# 指南：为何及如何使用Envoy作为跳板机代理Cloud SQL

本文档旨在复盘一次复杂的网络连接问题，并详细记录我们最终采用的解决方案：配置一台GCE虚拟机作为Envoy代理，以实现从外部网络访问VPC内部的私有Cloud SQL实例。

## 1. 最终方案：Envoy跳板机代理

**核心思路**：
我们利用一台拥有公网IP的GCE虚拟机作为“跳板机”。在这台机器上运行Envoy，并将其配置为TCP代理。Envoy监听一个公共端口（如`5432`），并将所有收到的流量转发到Cloud SQL实例的私有IP上。

**数据流**：
`[客户端(本地/GKE)]` -> `(连接GCE公网IP:5432)` -> `[GCE VM上的Envoy]` -> `(转发到Cloud SQL私网IP:5432)` -> `[Cloud SQL实例]`

---

## 2. 背景：为何选择此方案？Cloud SQL Auth Proxy的挑战

我们并非一开始就选择这个方案。在采用这个“跳板机”方案之前，我们尝试了所有官方推荐的标准方法，但都遇到了难以解决的障碍。以下是我们详细的排查历程：

### 阶段一：直接IP连接失败

我们的第一反应是直接从GKE Pod连接到Cloud SQL的私有IP。

- **问题**: `psql`客户端报告`Connection timed out`（连接超时）。
- **排查**:
    1.  **VPC防火墙**: 我们确认并添加了正确的防火墙规则，允许了所有VPC内部、GKE Pod和Service网段之间的通信。**问题依旧**。
    2.  **GKE网络策略**: 我们通过`kubectl get networkpolicy`确认集群中没有任何限制性的网络策略。**问题依旧**。
    3.  **IP伪装**: 我们通过部署`ip-masq-agent-config`的ConfigMap，确保了从Pod到私有IP的流量不会被错误地伪装。**问题依旧**。
    4.  **GCE测试**: 我们从一台普通的GCE VM上成功连接到了Cloud SQL，证明VPC主干网路由和防火墙是通的。

- **结论**: 问题特定于GKE环境，极有可能是GKE子网与Google服务网络之间的路由传播问题。

### 阶段二：Cloud SQL Auth Proxy的曲折尝试

在直接连接失败后，我们转向了Google官方**强烈推荐**的最佳实践——使用Cloud SQL Auth Proxy。我们认为这能绕过所有底层网络问题，但现实是残酷的。

- **尝试1: 本地使用v1旧版Proxy**
    - **现象**: 我们通过`apt`在本地安装了Proxy，但版本非常老（`1.17.0`）。启动后，`psql`连接直接卡死，Proxy日志仅显示`New connection`，没有任何错误。
    - **分析**: Proxy接收了连接，但在后台与Google通信时被无声地挂起。

- **尝试2: 修正v1版Proxy的参数**
    - **现象**: 我们发现v1版本不支持`--private-ip`参数，并根据其文档改用`-ip_address_types=PRIVATE`。**问题依旧**，`psql`连接仍然卡死。
    - **分析**: 参数正确后问题仍在，我们开始怀疑是IAM权限问题。

- **尝试3: 修正IAM权限**
    - **现象**: 我们发现Proxy默认使用了本地的`terraform`服务账号，而我们之前只给`vm-common`账号授权了。在为`terraform`账号添加了`Cloud SQL Client`角色后，**问题依旧**。
    - **分析**: 权限正确后问题仍在，这几乎排除了用户配置层面的错误。

- **尝试4: 升级到v2新版Proxy**
    - **现象**: 我们手动下载了最新的v2版Proxy。这次，我们得到了一个**决定性的错误信息**。Proxy日志明确报告：`failed to connect to instance: ... dial tcp 10.195.208.3:3307: i/o timeout`。
    - **最终诊断**: 这个错误表明，**Google自己的后台服务（Auth Proxy依赖的前端）无法连接到您Cloud SQL实例的私有IP**。这证实了问题出在Google Cloud平台内部一个我们无法直接干预的路由或服务配置上。

### 最终决策

既然官方推荐的工具本身都因平台问题而失败，继续调试已无意义。我们被迫采用一种创造性的、可以完全控制的解决方案——**搭建我们自己的代理服务器**，这就是Envoy跳板机方案的由来。

---

## 3. Envoy配置与测试

我们最终将`configs/envoy.yaml`配置为一个简单的TCP代理，并成功在GCE上部署和验证了其可行性。

### 3.1. 关键配置

```yaml
# configs/envoy.yaml

# ... (部分省略)
  listeners:
  - name: listener_psql
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 5432
    filter_chains:
    - filters:
      - name: envoy.filters.network.tcp_proxy
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
          stat_prefix: psql_tcp
          cluster: "cloud_sql_psql_cluster"
  clusters:
  - name: cloud_sql_psql_cluster
    connect_timeout: 5s
    type: STRICT_DNS
    load_assignment:
      cluster_name: cloud_sql_psql_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: "10.195.208.3" # Cloud SQL 私有IP
                port_value: 5432
# ... (部分省略)
```

### 3.2. 最终验证

我们从本地机器执行`psql`，连接到作为跳板机的GCE的公网IP `34.39.2.90`。

**命令**:
```bash
env PGPASSWORD="YOUR_DB_PASSWORD" psql -h s s -p 5432 -U nvd11 -d default_db -c "\l"
```

output
```bash
                                              List of databases
     Name      |       Owner       | Encoding |  Collate   |   Ctype    |            Access privileges            
---------------+-------------------+----------+------------+------------+-----------------------------------------
 cloudsqladmin | cloudsqladmin     | UTF8     | en_US.UTF8 | en_US.UTF8 | 
 default_db    | cloudsqlsuperuser | UTF8     | en_US.UTF8 | en_US.UTF8 | 
 postgres      | cloudsqlsuperuser | UTF8     | en_US.UTF8 | en_US.UTF8 | 
 template0     | cloudsqladmin     | UTF8     | en_US.UTF8 | en_US.UTF8 | =c/cloudsqladmin                       +
               |                   |          |            |            | cloudsqladmin=CTc/cloudsqladmin
 template1     | cloudsqlsuperuser | UTF8     | en_US.UTF8 | en_US.UTF8 | =c/cloudsqlsuperuser                   +
               |                   |          |            |            | cloudsqlsuperuser=CTc/cloudsqlsuperuser
(5 rows)

```

**结果**: 成功列出数据库，证明方案可行。
