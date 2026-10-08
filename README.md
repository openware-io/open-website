# open-website

Open IM 官网及静态内容站点（下载页 / 取消页 / 开发者页等），基于纯 HTML + Nginx + 容器化部署。

## 内容结构

```
html/       站点页面（download / cancel / developer 等）
nginx/      Nginx 站点配置
k8s/        Kubernetes 部署清单
docs/       部署与发布说明
scripts/    构建辅助脚本
Dockerfile  容器镜像构建
```

## 构建与部署

站点为静态页面，构建产物随容器镜像发布，部署方式见 `docs/` 与 `k8s/`。

本地 Kind 首次部署由 `open-im-server/scripts/deploy/k8s.ps1` 统一编排，官网入口为
`http://<本机地址>:30080/website/`。下载页和账号注销页使用同源 `/api/v1`，不在
静态文件中保存网关域名、内网地址、账号或密钥。

提交前执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## 许可证

[Apache License 2.0](LICENSE)，由 [openware-io](https://github.com/openware-io) 维护。
