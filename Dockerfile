# 语法: docker build -t vela-chat-web .
# 基于 nginx:alpine,体积小、适合托管静态站点
FROM nginx:1.27-alpine

LABEL maintainer="Vela Chat <xiaocaihong666888@outlook.com>"
LABEL description="Vela Chat official website static hosting image"

# 清理 nginx 默认配置与默认静态页
RUN rm -rf /etc/nginx/conf.d/default.conf /usr/share/nginx/html/*

# 自定义 nginx 配置
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# 静态站点文件
COPY html/ /usr/share/nginx/html/

# 权限修正(nginx worker 以 nginx 用户运行)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80

# 健康检查:nginx:alpine 自带 busybox wget
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
