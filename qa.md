刚我不是解释过了吗？
curl 127.0.0.1:10000 -> envoy (gcp_authn 从vm 绑定的sa 获取令牌) -> 带着令牌转发给后端cloudrun service
所以curl 命令不需要提供令牌的啊 不是吗？

你先用下面命令测试不使用proxy 能不能用vm绑定的sa调用后端cloud run svc
gcloud compute ssh my-envoy-test-vm-from-image-6 --zone=europe-west2-c --project=jason-hsbc --command="curl -v -H \"Authorization: Bearer \$(gcloud auth print-identity-token)\" https://py-api-svc-912156613264.europe-west2.run.app"

所以为什么在vm里调用代理不行？curl 127.0.0.1:10000  
帮我检查envoy配置or 日志