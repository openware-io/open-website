# open-website

GV Chat 官网及静态内容站点（下载页 / 取消页 / 开发者页等），基于纯 HTML + Nginx + 容器化部署。

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

## 许可证

[Apache License 2.0](LICENSE)，由 [openware-io](https://github.com/openware-io) 维护。
