#!/bin/bash
# 声明脚本使用 bash 执行

# 设置 -e 选项，确保脚本在任何命令失败时立即退出
set -e

# 设置 DEBIAN_FRONTEND 为 noninteractive，以防止 apt-get 在安装过程中弹出交互式对话框
export DEBIAN_FRONTEND=noninteractive

# 更新包列表，获取最新的软件包信息
sudo apt-get update

# 安装 vim 编辑器（-yq 表示自动确认且静默安装）
sudo apt-get install -yq vim

# 安装 Envoy 及其依赖所需的基础软件包 (https, ca-certs, curl, gpg, lsb-release)
sudo apt-get install -yq apt-transport-https ca-certificates curl gnupg lsb-release

# 创建一个用于测试的目录 /opt
sudo mkdir -p /opt

# 在 /opt 目录下创建一个 hello.txt 文件，写入 'hello world' 并打印内容以作验证
sudo touch /opt/hello.txt && sudo echo 'hello world' | sudo tee /opt/hello.txt && cat /opt/hello.txt

# 打印消息，表示基础软件包已安装成功
echo 'Basic packages installed successfully'

# 创建用于存放 GPG 密钥的目录
sudo mkdir -p /etc/apt/keyrings

# 从 Envoy 官方仓库下载 GPG 签名密钥，并解密后存放到指定位置
wget -O- https://apt.envoyproxy.io/signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/envoy-keyring.gpg

# 将 Envoy 的官方 APT 仓库源添加到系统的源列表中
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/envoy-keyring.gpg] https://apt.envoyproxy.io bullseye main" | sudo tee /etc/apt/sources.list.d/envoy.list

# 再次更新包列表，以包含新添加的 Envoy 仓库
sudo apt-get update

# 安装 Envoy 代理服务器
sudo apt-get install -yq envoy

# 使用 setcap 命令授予 Envoy 二进制文件绑定到特权端口（如 80）的能力
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/envoy

# 打印消息，表示 Envoy 已安装成功
echo 'Envoy installed successfully'

# 检查并打印 Envoy 的版本信息
envoy --version

# 打印消息，表示 Envoy 版本检查完成
echo 'Envoy version check completed successfully'

# 再次检查并打印 Envoy 的版本信息
envoy --version

# 检查并打印 gcloud SDK 的版本信息
gcloud --version

# 列出当前 gcloud 已认证的账户
gcloud auth list

# 创建用于存放 Envoy 配置文件的目录
sudo mkdir -p /etc/envoy

# 从 GCS 存储桶下载 Envoy 的配置文件到 /etc/envoy/ 目录下
sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.yaml /etc/envoy/envoy.yaml

# 打印消息，表示 Envoy 配置文件下载成功
echo 'Envoy config file downloaded successfully'

# 打印下载下来的 Envoy 配置文件内容以供检查
cat /etc/envoy/envoy.yaml

# 查找 Envoy 可执行文件的完整路径
ENVOY_PATH=$(which envoy)

# 如果找不到 Envoy 可执行文件，则打印错误并退出
if [ -z "$ENVOY_PATH" ]; then echo 'Envoy executable not found!' && exit 1; fi

# 将 Envoy 的可执行文件路径保存到临时文件中
echo "$ENVOY_PATH" | sudo tee /tmp/envoy_path.txt

# 打印消息，表示 Envoy 路径已保存
echo 'Envoy path saved to /tmp/envoy_path.txt'

# 从 GCS 存储桶下载 Envoy 的 systemd 服务单元文件
sudo gsutil cp gs://jason-hsbc_cloudbuild/envoyproxy/envoy.service /etc/systemd/system/envoy.service

# 打印消息，表示 systemd 服务文件下载成功
echo 'Envoy systemd service file downloaded successfully'

# 打印下载下来的 systemd 服务文件内容以供检查
sudo cat /etc/systemd/system/envoy.service

# 重新加载 systemd 管理守护进程，以识别新的服务文件
sudo systemctl daemon-reload

# 启用 Envoy 服务，使其在系统启动时自动运行
sudo systemctl enable envoy

# 打印消息，表示 Envoy 服务已重新加载并启用
echo 'Envoy systemd service reloaded and enabled'

# 在启动 Envoy 前，清理可能存在的旧共享内存文件
sudo rm -f /dev/shm/envoy_shared_memory_0

# 创建 Envoy 的日志文件
sudo touch /var/log/envoy.log

# 将日志文件的所有权更改为 envoy 用户和组，以便 Envoy 进程可以写入
sudo chown envoy:envoy /var/log/envoy.log

# 启动 Envoy 服务
sudo systemctl start envoy

# 等待 5 秒钟，给 Envoy 服务足够的时间来启动
sleep 5

# 打印消息，表示 Envoy 服务已启动
echo 'Envoy systemd service started'

# 打印分隔符，准备显示日志
echo 'trying to list Envoy service startup logs:'
echo '===============================/var/log/envoy-out.log==========================================='
echo '==================================/var/log/envoy.log========================================='

# 显示 Envoy 的自定义日志文件内容
sudo cat /var/log/envoy.log

# 打印分隔符
echo '==========================================================================='

# 使用 journalctl 查看最近 5 分钟内 Envoy 服务的系统日志
sudo journalctl -u envoy.service --no-pager --since "5 minutes ago"

# 打印消息，表示已列出启动日志
echo 'Envoy service startup logs listed'

# 打印分隔符
echo '==========================================================================='

# 检查并显示 Envoy 服务的当前状态
sudo systemctl status envoy --no-pager

# 打印消息，表示已检查服务状态
echo 'Envoy systemd service status checked'

# 打印分隔符，准备检查进程
echo '===========================checking envoy process========================================'

# 使用 ps 命令检查 Envoy 进程是否正在运行
ps aux | grep envoy

# 打印消息，表示已检查进程
echo 'Envoy process checked'
