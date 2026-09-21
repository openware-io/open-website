# ACK 静态官网部署实践记录

## 1. 目标与最终形态

本项目是一个纯静态前端站点，源码产物位于 `html/` 目录，通过 `nginx` 作为静态文件服务器对外提供访问。

最终上线架构如下：

1. 本地将静态站点打包成 Docker 镜像
2. 推送到阿里云 ACR 镜像仓库
3. ACK 集群中的 `Deployment` 运行该镜像
4. `Service` 将 Pod 暴露为集群内服务
5. `Nginx Ingress Controller` 接收公网流量
6. `Ingress` 按域名将请求转发到业务 `Service`
7. DNS 将 `example.com` / `www.example.com` 解析到 `nginx-ingress-lb` 的公网 IP
8. TLS 证书通过 Kubernetes `Secret` 挂给 `Ingress`

最终对外访问链路：

```text
浏览器
  -> DNS(A记录)
  -> nginx-ingress-lb 公网 IP / SLB
  -> nginx-ingress-controller
  -> Ingress(meta-cogni/xch-cms)
  -> Service(meta-cogni/xch-cms)
  -> Pod(meta-cogni/xch-cms-xxx)
  -> Nginx 容器
  -> html/index.html
```

## 2. 项目内相关文件

本次部署涉及的核心文件：

- `Dockerfile`
- `nginx/default.conf`
- `k8s/namespace.yaml`
- `k8s/deployment.yaml`
- `k8s/service.yaml`
- `k8s/ingress.yaml`
- `scripts/build-and-push.sh`
- `scripts/deploy.sh`

当前仓库已对齐的关键配置：

- 命名空间：`meta-cogni`
- 业务工作负载名：`xch-cms`
- 业务 Service 名：`xch-cms`
- Ingress 名：`xch-cms`
- TLS Secret 名：`openware-tls`
- 镜像仓库：
  - 推送使用公网域名：`crpi-2xbf44rg544imbew.cn-hangzhou.personal.cr.aliyuncs.com/meta-cogni/meta-cogni-cms`
  - 集群拉取优先使用 VPC 域名：`crpi-2xbf44rg544imbew-vpc.cn-hangzhou.personal.cr.aliyuncs.com/meta-cogni/meta-cogni-cms`

## 3. 资源职责说明

### 3.1 Deployment

`Deployment` 负责运行静态官网的 Nginx 容器。

职责：

- 指定镜像地址
- 控制副本数
- 定义健康检查
- 配置资源请求与限制
- 通过 `imagePullSecrets` 拉取私有 ACR 镜像

### 3.2 Service

`Service` 不是公网入口，它只是集群内的服务发现入口。

职责：

- 为 `xch-cms` Pod 提供稳定的 Service 名称
- 通过 `selector` 将流量转发到后端 Pod
- 被 `Ingress` 作为 backend 引用

本项目中，`Service` 类型使用 `ClusterIP` 即可。

### 3.3 Nginx Ingress Controller

这个组件是 ACK 安装的入口控制器，通常会自动创建两类资源：

1. `nginx-ingress-controller`
   - 负责读取集群中的 Ingress 规则
   - 根据 `host/path` 将请求转发到后端 Service

2. `nginx-ingress-lb`
   - 类型为 `LoadBalancer`
   - 会向阿里云申请公网 SLB/CLB
   - 对外暴露 `80/443`

它们通常位于 `kube-system` 命名空间。

### 3.4 Ingress

`Ingress` 是业务路由规则，而不是 Nginx 工作负载本身。

职责：

- 声明哪些域名归本项目处理
- 将域名流量路由到 `meta-cogni/xch-cms:80`
- 配置 TLS Secret 完成 HTTPS 证书绑定

## 4. 当前线上配置基准

### 4.1 命名空间

线上业务命名空间为：

```text
meta-cogni
```

### 4.2 域名

当前对外访问域名：

- `example.com`
- `www.example.com`

### 4.3 Ingress 关键规则

当前 `Ingress` 要点：

- `ingressClassName: nginx`
- `host: example.com`
- `host: www.example.com`
- backend Service：`xch-cms:80`
- TLS Secret：`openware-tls`

### 4.4 TLS Secret

注意：Nginx Ingress Controller 需要标准的 Kubernetes TLS Secret：

```text
type: kubernetes.io/tls
```

不能使用：

```text
type: IngressTLS
```

否则证书即使存在，Ingress Controller 也可能无法按标准方式加载。

## 5. 完整部署步骤

### 5.1 本地构建镜像

示例命令：

```bash
docker build --platform linux/amd64 -t crpi-2xbf44rg544imbew.cn-hangzhou.personal.cr.aliyuncs.com/meta-cogni/meta-cogni-cms:latest -f Dockerfile .
```

也可以使用脚本：

```bash
bash scripts/build-and-push.sh
```

说明：

- 构建目标平台固定为 `linux/amd64`
- 因 ACK 节点默认是 Linux AMD64

### 5.2 推送镜像到 ACR

示例命令：

```bash
docker push crpi-2xbf44rg544imbew.cn-hangzhou.personal.cr.aliyuncs.com/meta-cogni/meta-cogni-cms:latest
```

建议记录每次推送的 digest，用于线上回滚和固定版本。

### 5.3 ACK 集群拉私有镜像

若镜像仓库为私有，需要在业务命名空间中创建拉取凭证：

```bash
kubectl -n meta-cogni create secret docker-registry acr-registry-secret \
  --docker-server=crpi-2xbf44rg544imbew-vpc.cn-hangzhou.personal.cr.aliyuncs.com \
  --docker-username='你的ACR用户名' \
  --docker-password='你的ACR密码'
```

`Deployment` 中通过：

```yaml
imagePullSecrets:
  - name: acr-registry-secret
```

引用该 secret。

### 5.4 部署工作负载

应用资源：

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

或使用脚本：

```bash
bash scripts/deploy.sh
```

### 5.5 确认 Pod 正常

```bash
kubectl -n meta-cogni get deploy,pod
kubectl -n meta-cogni describe pod <pod-name>
```

应确认：

- Pod 为 `Running`
- 探针健康
- 没有镜像拉取失败

### 5.6 确认 Service 正常选中 Pod

```bash
kubectl -n meta-cogni get svc xch-cms
kubectl -n meta-cogni get endpointslice
```

如果 `endpointslice` 有 Pod IP，说明 Service 已成功关联到业务 Pod。

### 5.7 安装 Nginx Ingress Controller

在 ACK 控制台安装 `Nginx Ingress Controller`，而不是 `ALB/NLB Ingress Controller`。

建议：

- 公网入口
- 开启 `80/443`
- 使用默认最小可用资源

安装完成后，在 `kube-system` 中会出现：

- `nginx-ingress-controller`
- `nginx-ingress-lb`

### 5.8 配置域名 DNS

DNS 推荐配置：

- `@ -> A -> nginx-ingress-lb 公网 IP`
- `www -> A -> nginx-ingress-lb 公网 IP`

不建议仅配置 `*` 泛解析来替代 `@` 和 `www`。

### 5.9 配置 TLS 证书

证书最终必须进入 Kubernetes Secret。

如果手头有证书和私钥文件，可创建：

```bash
kubectl -n meta-cogni create secret tls openware-tls \
  --cert=fullchain.pem \
  --key=private.key
```

注意：

- Secret 命名空间必须是 `meta-cogni`
- Secret 名称必须与 Ingress 中的 `secretName` 一致
- 建议使用 fullchain，避免证书链不完整

## 6. 这次实际踩过的关键问题

### 6.1 只创建了 Pod，没有创建 Service/Ingress

现象：

- 页面返回 `503 Service Temporarily Unavailable`

原因：

- 域名已经命中 Ingress Controller
- 但 `meta-cogni` 中没有 Service/Ingress，后端链路断了

排查命令：

```bash
kubectl -n meta-cogni get ingress
kubectl -n meta-cogni get svc
kubectl -n meta-cogni get endpointslice
kubectl -n meta-cogni get pod --show-labels
```

### 6.2 Ingress 建错命名空间

当时存在旧资源：

```text
default/ng-cms-web
```

问题：

- 域名路由建在 `default`
- 业务 Pod 在 `meta-cogni`
- 导致路由指向错误后端或找不到 Service

正确做法：

- 业务 `Ingress` 与 `Service` 应统一在 `meta-cogni`

### 6.3 Service selector 与 Pod 标签不匹配

这是最容易被忽略的问题。

必须确保：

- `Service.selector`
- `Deployment.template.metadata.labels`

完全对齐，否则 Service 选不中 Pod。

### 6.4 私有 ACR 拉取失败

表现：

- `ImagePullBackOff`
- `ErrImagePull`

原因：

- ACK 节点拉取私有镜像未配置凭证

解决：

- 创建 `acr-registry-secret`
- `Deployment` 中引用 `imagePullSecrets`

### 6.5 使用了错误类型的证书 Secret

实际踩坑：

- Secret 类型被建成了 `IngressTLS`

而 Nginx Ingress Controller 需要：

```text
kubernetes.io/tls
```

后续已修正为标准 TLS Secret。

### 6.6 误以为阿里云证书管理中的证书会自动被 ACK 使用

实际上不会。

证书在阿里云证书管理中存在，不代表 Kubernetes 里已有可用 Secret。

必须额外导入到 ACK 集群。

### 6.7 CloudShell/集群终端内 curl 443 超时的误判

在 ACK 终端或容器环境里直接访问同一个公网 SLB，可能因为网络回环/NAT 行为导致超时。

这类超时不一定代表公网 443 对外不可用。

更可靠的验证方式：

- 本机浏览器
- 本机 `curl.exe`
- 外部网络/手机流量

### 6.8 本机 VPN / 代理影响 DNS 和 HTTPS 结果

本次验证时，本机 VPN 会导致：

- DNS 解析结果与公网检测不一致
- 浏览器缓存旧证书或旧解析

验证线上证书是否正确时，应：

- 关闭 VPN/代理
- 清除浏览器 SSL 状态
- 使用无痕窗口
- 必要时换手机流量测试

## 7. 关键排查命令清单

### 7.1 基础资源状态

```bash
kubectl -n meta-cogni get deploy,pod,svc,ingress
kubectl -n meta-cogni get endpointslice
kubectl -n meta-cogni describe ingress xch-cms
```

### 7.2 查看所有 Ingress

```bash
kubectl get ingress -A -o wide
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.rules[*]}{.host}{" "}{end}{"\n"}{end}'
```

### 7.3 查看 Ingress Controller

```bash
kubectl -n kube-system get pods | grep nginx-ingress-controller
kubectl -n kube-system describe svc nginx-ingress-lb
kubectl -n kube-system logs deployment/nginx-ingress-controller --tail=300
```

### 7.4 查看 Secret

```bash
kubectl -n meta-cogni get secret
kubectl -n meta-cogni get secret openware-tls -o yaml
kubectl -n meta-cogni get secret openware-tls -o jsonpath='{.type}{"\n"}'
```

### 7.5 查看线上返回证书

本机 PowerShell：

```powershell
curl.exe -vk https://example.com/ -o NUL
curl.exe -vk https://www.example.com/ -o NUL
```

如果本机有 OpenSSL：

```bash
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
echo | openssl s_client -connect www.example.com:443 -servername www.example.com 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

## 8. 当前推荐运维动作

### 8.1 发布新版本

1. 修改前端静态资源
2. 重新构建镜像并推送
3. 更新 Deployment 镜像或 rollout restart

例如：

```bash
kubectl -n meta-cogni rollout restart deployment/xch-cms
```

### 8.2 回滚

推荐使用具体 digest，而不是长期只依赖 `latest`。

集群实际引用建议格式：

```text
crpi-2xbf44rg544imbew-vpc.cn-hangzhou.personal.cr.aliyuncs.com/meta-cogni/meta-cogni-cms@sha256:<digest>
```

### 8.3 证书续期

证书续期后，需要同步更新 `meta-cogni/meta-cogni-cms6688-tls`。

更新后可重启 ingress controller 或等待自动 reload。

## 9. 这次落地后的经验总结

### 9.1 先搞清楚 Kubernetes 四层资源关系

很多问题的根源不是配置值错，而是没先建立正确的资源认知：

- Pod 跑应用
- Service 做服务发现
- Ingress 做七层路由
- Ingress Controller 做实际转发
- LoadBalancer 对外暴露公网入口

### 9.2 命名空间必须统一

一旦命名空间不统一，很容易出现：

- Ingress 在 `default`
- Pod 在 `meta-cogni`
- Service 不存在

结果就是：

- 503
- 后端找不到
- 控制台看起来“都创建了”，但流量实际断链

### 9.3 证书存在不代表证书生效

必须同时满足：

1. Secret 在正确 namespace
2. Secret 类型是 `kubernetes.io/tls`
3. Ingress `secretName` 指向它
4. Ingress Controller 正常加载
5. 浏览器拿到的就是这张证书

### 9.4 线上验证一定要分清“公网问题”和“本机问题”

如果本机开了 VPN、代理、HTTPS 检查软件：

- 解析结果可能被劫持
- 浏览器可能提示未认证
- 但服务器端其实已经配置正确

因此验证顺序应该是：

1. 集群内资源是否完整
2. Ingress 是否有 backend
3. Secret 是否正确
4. 公网入口是否返回正确证书
5. 最后再看本机浏览器环境

## 10. 推荐最终状态自检清单

上线前至少确认以下项目全部满足：

- `meta-cogni` 命名空间存在
- `Deployment/xch-cms` 为 `Ready`
- `Service/xch-cms` 存在
- `EndpointSlice` 有后端 Pod IP
- `Ingress/xch-cms` 存在
- `ingressClassName: nginx`
- `example.com` 和 `www.example.com` 都在规则里
- `openware-tls` 存在且类型为 `kubernetes.io/tls`
- DNS A 记录指向 `nginx-ingress-lb` 公网 IP
- 本机关闭 VPN 后访问 `https://example.com` 正常

