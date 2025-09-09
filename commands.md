```bash
docker run --name=envoy -d \
  -p 80:10000 \
  -v $(pwd)/manifests/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:latest
```