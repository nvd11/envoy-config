FROM ubuntu:22.04

# 设置环境变量以避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 更新包列表并安装必要的工具
RUN apt-get update && apt-get install -y \
    curl \
    gnupg2 \
    ca-certificates \
    iputils-ping \
    dnsutils \
    net-tools \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 添加Envoy的APT仓库
RUN curl -sL 'https://deb.dl.getenvoy.io/public/gpg.8115BA8E629CC074.key' | gpg --dearmor -o /usr/share/keyrings/getenvoy-keyring.gpg
RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy-keyring.gpg] https://deb.dl.getenvoy.io/public/deb/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/getenvoy.list

# 安装Envoy
RUN apt-get update && apt-get install -y getenvoy-envoy && rm -rf /var/lib/apt/lists/*

# 创建Envoy配置目录
RUN mkdir -p /etc/envoy

# 复制默认配置文件（可选，您可能需要挂载自己的配置文件）
# COPY envoy.yaml /etc/envoy/

# 暴露Envoy的默认端口
EXPOSE 9901 10000

# 设置容器启动时启动Envoy
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml", "--service-cluster", "my-cluster"]

# 健康检查（可选）
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:9901/server_info || exit 1