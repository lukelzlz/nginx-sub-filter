FROM debian:bookworm-slim as builder
# 安装依赖
RUN apt-get update && \
    apt-get install -y \
        git \
        build-essential \
        libpcre3-dev \
        zlib1g-dev \
        libssl-dev \
        automake \
        autoconf \
        libtool \
        wget
# 下载Nginx源码
RUN wget https://nginx.org/download/nginx-1.25.3.tar.gz && \
    tar -zxvf nginx-1.25.3.tar.gz && \
    mv nginx-1.25.3 nginx-src
# 下载subs-filter模块
RUN mkdir -p /tmp/modules && \
    git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git /tmp/modules/subs-filter
# 编译模块
WORKDIR /nginx-src
RUN ./configure \
        --with-compat \
        --add-dynamic-module=/tmp/modules/subs-filter \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_sub_module \
        --with-threads \
        --with-http_v2_module \
        --with-file-aio \
        --with-http_gzip_static_module \
        --with-http_auth_request_module && \
    make modules

# 最终镜像
FROM nginx:stable

# 从builder阶段复制编译好的模块
COPY --from=builder \
     /tmp/nginx-$(cat /tmp/nginx_version | cut -d'/' -f2)/objs/ngx_http_subs_filter_module.so \
     /usr/lib/nginx/modules/

# 启用模块
RUN echo "load_module modules/ngx_http_subs_filter_module.so;" > /etc/nginx/modules-enabled/50-subs-filter.conf

# 复制配置文件（这里使用你提供的配置）
COPY nginx.conf /etc/nginx/nginx.conf

# 验证模块加载
RUN nginx -t 2>&1 | grep -q "subs filter module" && echo "Module loaded successfully" || (echo "Module load failed" && exit 1)
