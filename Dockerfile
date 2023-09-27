# custom nginx by vkom
FROM alpine:latest as builder
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

ARG IN_NGINX_VERSION=1.24.0
ARG IN_NGINX_PCRE2_VERSION=pcre2-10.40
ARG IN_NGXMOD_GRAPHITE_VERSION=master # v3.1
ARG IN_NGXMOD_TSTCK_VERSION=master
ARG IN_NGXMOD_PAM_VERSION=1.5.3
ARG IN_NGXMOD_RDNS_VERSION=master
ARG IN_NGXMOD_HEADMR_VERSION=master
ARG IN_NGXMOD_BROTLI_VERSION=master
ARG IN_NGXMOD_VTS_VERSION=0.2.1

ENV NGINX_VERSION=$IN_NGINX_VERSION
ENV NGINX_PCRE2_VERSION=$IN_NGINX_PCRE2_VERSION
ENV NGXMOD_GRAPHITE_VERSION=$IN_NGXMOD_GRAPHITE_VERSION
ENV NGXMOD_TSTCK_VERSION=$IN_NGXMOD_TSTCK_VERSION
ENV NGXMOD_PAM_VERSION=$IN_NGXMOD_PAM_VERSION
ENV NGXMOD_RDNS_VERSION=$IN_NGXMOD_RDNS_VERSION
ENV NGXMOD_HEADMR_VERSION=$IN_NGXMOD_HEADMR_VERSION
ENV NGXMOD_BROTLI_VERSION=$IN_NGXMOD_BROTLI_VERSION
ENV NGXMOD_VTS_VERSION=$IN_NGXMOD_VTS_VERSION

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# install build dependencies
RUN apk add --no-cache build-base curl git gnupg linux-headers \
		libc-dev openssl-dev pcre-dev zlib-dev libxslt-dev gd-dev geoip-dev linux-pam-dev

# create builddir
RUN mkdir -p /usr/src/nginx \
	&& mkdir -p /usr/local/nginx
WORKDIR /usr/src/nginx

# download nginx & nginx modules
RUN curl -f -sS -L https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/PCRE2Project/pcre2/releases/download/${NGINX_PCRE2_VERSION}/${NGINX_PCRE2_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/mailru/graphite-nginx-module/archive/${NGXMOD_GRAPHITE_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/kyprizel/testcookie-nginx-module/archive/${NGXMOD_TSTCK_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/sto/ngx_http_auth_pam_module/archive/v${NGXMOD_PAM_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/flant/nginx-http-rdns/archive/${NGXMOD_RDNS_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/openresty/headers-more-nginx-module/archive/${NGXMOD_HEADMR_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/vozlt/nginx-module-vts/archive/v${NGXMOD_VTS_VERSION}.tar.gz | tar zxC .
	# && curl -f -sS -L https://github.com/google/ngx_brotli/archive/${NGXMOD_BROTLI_VERSION}.tar.gz | tar zxC .

# patch nginx sources && configure
WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}
RUN patch -p1 < ../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION}/graphite_module_v1_15_4.patch \
	&& ./configure --help ||: \
	&& ../${NGINX_PCRE2_VERSION}/configure --help ||: \
	&& ./configure \
	--user=nginx \
	--group=nginx \
	--prefix=/etc/nginx \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--sbin-path=/usr/sbin/nginx \
	--modules-path=/usr/lib/nginx/modules \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--with-pcre=../${NGINX_PCRE2_VERSION} \
#	--with-pcre-opt='--enable-pcre2-16' \ # https://stackoverflow.com/questions/4655250/difference-between-utf-8-and-utf-16
	--with-pcre-jit \
	--without-select_module \
	--without-poll_module \
	--without-http_ssi_module \
	--without-http_uwsgi_module \
	--without-http_scgi_module \
	--without-http_memcached_module \
	--without-http_empty_gif_module \
	--without-http_browser_module \
	--without-http_userid_module \
	--with-threads \
	--with-file-aio \
	--with-http_ssl_module \
	--with-http_v2_module \
	--with-http_realip_module \
	--with-http_auth_request_module \
	--with-http_sub_module \
	--with-http_secure_link_module\
	--with-http_stub_status_module \
	--with-http_dav_module \
	--with-http_realip_module \
	--with-http_addition_module \
	--with-http_slice_module \
	--with-stream=dynamic \
	--with-stream_ssl_preread_module \
	--with-stream_realip_module \
	--with-http_xslt_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_geoip_module=dynamic \
	--with-compat \
	--add-dynamic-module=../ngx_http_auth_pam_module-${NGXMOD_PAM_VERSION} \
	# --add-dynamic-module=../ngx_brotli-${NGXMOD_BROTLI_VERSION} \
	--add-module=../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION} \
	--add-module=../testcookie-nginx-module-${NGXMOD_TSTCK_VERSION} \
	--add-module=../nginx-http-rdns-${NGXMOD_RDNS_VERSION} \
	--add-module=../headers-more-nginx-module-${NGXMOD_HEADMR_VERSION} \
	--add-module=../nginx-module-vts-${NGXMOD_VTS_VERSION} \
	--with-cc-opt='-O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic'

# make && make install
RUN make -j$(( `nproc` + 1 )) \
	&& make DESTDIR=/usr/local/nginx install

# mkdir for dynamic modules, configs, ssl, caches
WORKDIR /usr/local/nginx
RUN mkdir -p /usr/lib/nginx/modules \
	&& ln -s ../../usr/lib/nginx/modules etc/nginx/modules \
	&& mkdir etc/nginx/conf.d \
	&& mkdir etc/nginx/ssl \
	&& mkdir -p var/cache/nginx/client_temp \
	&& mkdir -p var/cache/nginx/proxy_temp \
	&& mkdir -p var/cache/nginx/fastcgi_temp

# strip all bins and libs
RUN strip usr/sbin/nginx* \
	&& strip usr/lib/nginx/modules/*so


# RELEASE PACKAGE
FROM alpine:latest
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

# user & group management
RUN addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx

# copy files from build container && sync to root && source remove
RUN apk add --no-cache rsync \
	&& mkdir -p /usr/loca/nginx
COPY --from=builder /usr/local/nginx /usr/local/nginx
RUN rsync -aAxXv --numeric-ids --progress /usr/local/nginx/ / \
	&& rm -rf /usr/local/nginx \
	&& apk del rsync

# install run dependencies
RUN apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp \
	&& apk add --no-cache --virtual .nginx-rundeps $( \
		scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst	\
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
			| xargs \
		) \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/local/bin/

# install tzdata so users could set the timezones through the environment variables
RUN apk add --no-cache tzdata

# update chmod for nginx ssl dir
RUN chown root:root /etc/nginx/ssl \
	&& chmod 0100 /etc/nginx/ssl

# remove nginx.conf for future mounting:
RUN rm -vf /etc/nginx/nginx.conf

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]

#	\
#	# Bring in gettext so we can get `envsubst`, then throw
#	# the rest away. To do this, we need to install `gettext`
#	# then move `envsubst` out of the way so `gettext` can
#	# be deleted completely, then move `envsubst` back.
#	&& apk add --no-cache --virtual .gettext gettext \
#	&& mv /usr/bin/envsubst /tmp/ \
#	\
#	&& runDeps="$( \
#		scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
#			| tr ',' '\n' \
#			| sort -u \
#			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
#	)" \
#	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
#	&& apk del .build-deps \
#	&& apk del .gettext \
#	&& mv /tmp/envsubst /usr/local/bin/