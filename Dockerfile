# 阶段1：编译模块
FROM debian:bookworm-slim as builder

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

# 下载Nginx源码（版本硬编码）
RUN wget https://nginx.org/download/nginx-1.24.0.tar.gz && \
    tar -zxvf nginx-1.24.0.tar.gz && \
    mv nginx-1.24.0 nginx-src

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

# ----------------------------
# 阶段2：生成最终镜像
FROM nginx:1.24.0
# 安装运行时依赖
RUN apt-get update && \
    apt-get install -y \
        libpcre3 \
        zlib1g \
        openssl \
        binutils && \  # 添加objdump用于模块验证
    rm -rf /var/lib/apt/lists/*

# 从builder阶段复制模块
COPY --from=builder /nginx-src/objs/ngx_http_subs_filter_module.so /usr/lib/nginx/modules/

# 先复制用户配置
COPY nginx.conf /etc/nginx/nginx.conf

# 插入模块加载指令到主配置顶部（覆盖后操作）
RUN echo "load_module modules/ngx_http_subs_filter_module.so;" | cat - /etc/nginx/nginx.conf > /tmp/nginx.conf && \
    mv /tmp/nginx.conf /etc/nginx/nginx.conf

# 增强验证步骤
RUN nginx -t && \
    nginx -T 2>&1 | grep -q "subs filter module" && \
    objdump -p /usr/lib/nginx/modules/ngx_http_subs_filter_module.so | grep -q "SONAME" && \
    echo "Module verification passed" || (echo "Module verification failed" && exit 1)