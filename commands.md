```bash
docker run --name=envoy -d \
  -p 80:10000 \
  -v /home/gateman/projects/envoy-config/configs/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.33-latest
```