```bash
docker run --name=envoy -d \
  -p 80:10000 \
  -v /home/gateman/projects/envoy-config/configs/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.33-latest


docker stop envoy; docker rm $(docker ps -aq -f status=exited); docker run --name=envoy -d   -p 10000:10000 -p 9901:9901  -v /home/gateman/projects/envoy-config/configs/envoy.yaml:/etc/envoy/envoy.yaml   envoyproxy/envoy:v1.33-latest

docker build -t envoy-ubuntu .

docker run -d --name envoy-ubuntu -p 9901:9901 -p 10000:10000 envoy-ubuntu
```

帮我写1个docker file
1.基于ubuntu
2. 下载安装envoy
3. 安装ping 等网络工具

3. 容器启动时启动envoy

帮我写一个简单的envoy.yaml

1. 适配 envoy 1.33 版本
2. envoy 跑在docker 内， docker所在的主机地址是10.0.1.223


当我访问http://10.0.1.223:10000时 重定向去b站主页