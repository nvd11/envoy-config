# 史诗级调试：从 Envoy 无响应到全自动化 MIG 滚动更新

本文档详细记录了一次从服务无响应开始，到最终实现 Envoy 代理集群自动化滚动更新的完整端到端问题排查过程。这个过程充满了反转和对 GCP 服务非标准行为的探索，最终形成了一套健壮的、基于 IaC 的解决方案。

## 1. 初始问题：深渊凝视

一切始于一个简单的 `curl` 命令，它目标是我们部署在 `http://www.jpgcp.cloud` 上的聊天服务。然而，它只返回了无尽的等待，没有任何响应。

```bash
curl -N -X POST "http://www.jpgcp.cloud/py-chat-deepseek-svc/api/v1/chat" ...
```

## 2. 排查之旅：曲折的道路

### 第1站：Cloud Run 日志 - 第一个“烟雾弹”
- **怀疑**: 后端 Cloud Run 服务在调用上游 LLM 时被阻塞。
- **行动**: 检查 Cloud Run 日志。
- **发现**: 日志中充满了对 `.env` 等敏感文件的扫描请求，并返回 `403 Not Authenticated`。这证明了我们的服务是私有的，但这些日志与我们的 `curl` 请求无关，它们是来自互联网的背景噪音。

### 第2站：基础设施深潜 - 发现冰山
- **关键信息**: 用户指出，架构中存在一个 **Envoy 代理**，部署在 GCE 虚拟机上，由**代管实例组 (MIG)** 管理，并负责处理 GCP 身份验证。
- **修正方向**: 问题焦点从 Cloud Run 转移到 Envoy 代理、GCE 虚拟机和 MIG。

### 第3站：配置审计 - 冰山一角
- **怀疑**: 运行在 GCE 上的 Envoy 配置可能不正确或已过时。
- **行动**: SSH 连接到 MIG 中的一台虚拟机，读取 `/etc/envoy/envoy.yaml`。
- **发现**: 服务器上的 `envoy.yaml` 是一个**旧版本**，完全没有我们需要的路由规则。而本地代码库中的版本是更新、更完整的。
- **结论**: 部署流程存在问题，最新的配置没有被应用到正在运行的实例上。**必须通过更新 MIG 的实例模板来解决。**

### 第4站：自动化流程调试 - 真正的迷宫
我们的目标转变为：创建一个自动化的 Cloud Build 管道，用于正确地更新 MIG。这个过程充满了陷阱。

- **目标**: 创建一个 `cloudbuild_refresh_envoy_proxy.yaml` 管道，并用 Cloud Scheduler 定时触发它。
- **遇到的坑与解决方案**:
    1.  **`400 Bad Request` (无效的 Body)**: 我们尝试了多种 `curl` 请求体，包括 `{"branchName":...}`、`{}`、`{"source":{"revision":...}}`，均被 API 以各种矛盾的理由拒绝。
    2.  **`401 Unauthenticated` (错误的令牌)**: 我们发现调用 Google Cloud API 需要 **Access Token** (`print-access-token`)，而不是用于服务间认证的 ID Token (`print-identity-token`)。这是一个关键的转变。
    3.  **`403 Permission Denied` (权限不足)**: 即使使用了正确的令牌和看似正确的 Body，API 仍然拒绝，提示 `Couldn't read commit`。我们依次为调用者服务账号 (`terraform@...`) 添加了 `Service Account Token Creator` 和 `Cloud Build Editor` 角色。
    4.  **`gcloud` 命令的陷阱**: 我们发现 `gcloud builds list` 默认不显示区域性构建，必须添加 `--region` 标志才能看到真相。`gcloud scheduler jobs update` 不支持直接修改 Headers。

### 第5站：最终的顿悟 (用户的洞察)
- **关键发现**: 在我们几乎要放弃时，用户在网页控制台中发现了一个决定性的线索：`envoy-config` 代码库的连接类型是 **Cloud Source Repositories**，并且带有一个**黄色感叹号**。
- **根本原因大揭秘**:
    - **连接方式不匹配**: 我们的 Terraform 代码和 API 调用都在尝试使用**第二代**的 "Cloud Build GitHub App" 连接方式，但 GCP 项目中实际存在的却是**第一代**的、已损坏的 "Cloud Source Repositories" 镜像连接。
    - **`403` 的真正原因**: `Couldn't read commit` 错误并非我们之前猜测的任何 IAM 角色问题，而是 Cloud Build 在执行时，被引导到了一个错误的、已损坏的源代码位置。

## 3. 最终解决方案：拨云见日

### 3.1. 核心修正 (手动)

在 GCP 控制台中，**删除旧的 Cloud Source Repositories 连接，然后通过 "Manage Repositories" 流程，使用 Cloud Build GitHub App 重新连接 `envoy-config` 代码库。** 这是解决所有问题的基石。

### 3.2. 意外的发现：Terraform 配置与 API 行为的微妙关系

在解决了代码库连接问题后，我们最终厘清了 Terraform 配置、触发器类型和 API 行为之间的复杂关系。

#### 错误的 Terraform 配置 (导致 CSR 镜像问题)

我们最初尝试将触发器改为“手动模式”时，使用了 `trigger_template`。这种方式在 Terraform 中会产生一个意想不到的副作用：它不会使用现有的 GitHub App 连接，而是会尝试创建一个旧版的、损坏的 **Cloud Source Repositories 镜像**，这正是导致 `Couldn't read commit` 错误的根源。

```terraform
# 错误的配置：这会创建一个损坏的 CSR 镜像，而不是使用 GitHub App 连接
resource "google_cloudbuild_trigger" "envoy-proxy-refresh-trigger" {
  name     = "envoy-proxy-refresh-trigger"
  location = var.region_id

  trigger_template {
    project_id = var.project_id
    repo_name  = "envoy-config"
    branch_name = "main"
  }
  # ...
}
```

#### 正确的 Terraform 配置

要正确地关联到通过 **GitHub App** 连接的代码库，我们必须在 Terraform 中使用 `github` 块。

```terraform
# 正确的配置：这能正确关联到 GitHub App 连接
resource "google_cloudbuild_trigger" "envoy-proxy-refresh-trigger" {
  name = "envoy-proxy-refresh-trigger"
  location = var.region_id

  github {
    name  = "envoy-config"
    owner = "nvd11"
    push {
      branch = "^main$" # 使用正则表达式确保精确匹配
    }
  }
  # ...
}
```

#### 非标准的 API 行为

最令人惊讶的发现是，即使触发器在 Terraform 中被定义为 `github` 类型（理论上是 Push 触发器），Cloud Build 的 `:run` API 端点**依然可以**手动调用它，只要提供了正确的认证（Access Token）和我们最终确定的请求体。这与常规理解和部分文档相悖，是实践中得出的宝贵经验。

### 3.3. 最终的自动化代码

**1. Terraform (`scheduler/envoy_proxy_refresh_scheduler.tf`)**

我们最终通过 Terraform 创建了一个完美的 Cloud Scheduler 作业，它使用了正确的认证方式和我们通过 `curl` 最终试出的正确请求体。

```terraform
# ... data sources for trigger and service account ...

resource "google_cloud_scheduler_job" "refresh_envoy_mig_daily" {
  name        = "refresh-envoy-mig-daily"
  description = "Daily job to refresh the Envoy MIG by running a Cloud Build trigger."
  schedule    = "0 3 * * *" # Daily at 3:00 AM UTC
  time_zone   = "Etc/UTC"
  project     = var.project_id
  region      = var.region

  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/${data.google_cloudbuild_trigger.refresh_trigger.id}:run"
    
    # The final, correct request body
    body = base64encode("{\"source\": {\"projectId\": \"${var.project_id}\", \"repoName\": \"envoy-config\", \"branchName\": \"main\"}}")
    
    headers = {
      "Content-Type" = "application/json"
    }

    # This uses an Access Token, which is correct for calling Google APIs
    oauth_token {
      service_account_email = data.google_service_account.scheduler_sa.email
    }
  }
}
```

**2. Cloud Build (`cloudbuild_refresh_envoy_proxy.yaml`)**

这个文件负责实际的滚动更新，它在调试过程中被我们打磨得非常健壮。

```yaml
steps:
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  id: create_instance_template
  # ... (creates a new instance template from the latest image with correct IP, tags, etc.)
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
  id: rolling_update_mig
  # ... (finds the current MIG and applies the new template)
options:
  logging: CLOUD_LOGGING_ONLY
```

通过这一系列艰苦卓绝的排查，我们不仅修复了所有问题，还建立了一套真正可靠的自动化运维流程，并对 GCP 的一些非标准行为有了更深刻的理解。
