# custom nginx by vkom

## STAGE - BORINGSSL BUILD ##
FROM alpine:latest as sslbuilder
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache git curl gnupg build-base cmake linux-headers perl libunwind-dev go

WORKDIR /usr/src/boringssl
RUN git clone --depth=1 https://boringssl.googlesource.com/boringssl . \
  && mkdir -v -p build .openssl/lib .openssl/include \
  && ln -v -sf ../../include/openssl .openssl/include/openssl \
  && touch .openssl/include/openssl/ssl.h \
  && cmake -B./build -H. \
  && make -C./build -j$(( `nproc` + 1 )) \
  && cp -v build/crypto/libcrypto.a build/ssl/libssl.a .openssl/lib/ \
	&& ls -lah . build .openssl


## STAGE - NGINX BUILD ##
FROM alpine:latest as builder
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

ARG IN_NGINX_VERSION=1.24.0
ARG IN_NGINX_PCRE2_VERSION=pcre2-10.42
ARG IN_NGXMOD_GRAPHITE_VERSION=master # v3.1
ARG IN_NGXMOD_HEADMR_VERSION=master
ARG IN_NGXMOD_VTS_VERSION=0.2.2

ENV NGINX_VERSION=$IN_NGINX_VERSION
ENV NGINX_PCRE2_VERSION=$IN_NGINX_PCRE2_VERSION
ENV NGXMOD_GRAPHITE_VERSION=$IN_NGXMOD_GRAPHITE_VERSION
ENV NGXMOD_HEADMR_VERSION=$IN_NGXMOD_HEADMR_VERSION
ENV NGXMOD_VTS_VERSION=$IN_NGXMOD_VTS_VERSION

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# install build dependencies
RUN apk add --no-cache build-base curl git gnupg linux-headers \
		libc-dev pcre-dev zlib-dev libxslt-dev gd-dev geoip-dev linux-pam-dev

WORKDIR /usr/src/nginx
COPY --from=sslbuilder /usr/src/boringssl ./boringssl

# download nginx & nginx modules
RUN curl -f -sS -L https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/PCRE2Project/pcre2/releases/download/${NGINX_PCRE2_VERSION}/${NGINX_PCRE2_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/mailru/graphite-nginx-module/archive/${NGXMOD_GRAPHITE_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/openresty/headers-more-nginx-module/archive/${NGXMOD_HEADMR_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/vozlt/nginx-module-vts/archive/v${NGXMOD_VTS_VERSION}.tar.gz | tar zxC .

# get path for nginx 1.17.7+ from Cloudflare (Dynamic TLS records patch CloudFlare support)
RUN curl -f -sS -L https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.17.7%2B.patch -o dynamic_tls_records.patch

# patch nginx sources && configure
WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}
RUN patch -p1 < ../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION}/graphite_module_v1_15_4.patch \
	&& patch -p1 < ../dynamic_tls_records.patch \
	&& ./configure --help ||: \
	&& ../${NGINX_PCRE2_VERSION}/configure --help ||: \
	&& ./configure \
	--build="MindHunter86's custom build with BoringSSL" \
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
	--without-http_memcached_module \
	--without-http_empty_gif_module \
	--without-http_userid_module \
	--without-http_autoindex_module \
	--without-http_fastcgi_module \
	--without-http_uwsgi_module \
	--without-http_scgi_module \
	--without-http_grpc_module \
	--without-http_browser_module \
	--with-compat \
	--with-threads \
	--with-file-aio \
	--with-http_ssl_module \
	--with-http_v2_module \
	--with-http_realip_module \
	--with-http_auth_request_module \
	--with-http_sub_module \
	--with-http_secure_link_module\
	--with-http_stub_status_module \
	--with-http_realip_module \
	--with-http_gzip_static_module \
	--with-http_geoip_module=dynamic \
	--add-module=../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION} \
	--add-module=../headers-more-nginx-module-${NGXMOD_HEADMR_VERSION} \
	--add-module=../nginx-module-vts-${NGXMOD_VTS_VERSION} \
	--with-ld-opt='-L../boringssl/.openssl/lib/' \
	--with-cc-opt='-I../boringssl/.openssl/include/ -O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic'


	# --with-ld-opt='-L../boringssl/.openssl/lib/ -Wl,-E -Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,-as-needed -pie' \

# --with-cc-opt="-g -O2 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -I $BUILDROOT/boringssl/.openssl/include/" \
# --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -L $BUILDROOT/boringssl/.openssl/lib/" \

# fastopen
#--with-cc-opt='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic -DTCP_FASTOPEN=23'
#--with-ld-opt='-Wl,-z,relro -Wl,-E'

# debian apt repo
#--with-cc-opt='-g -O2 -fdebug-prefix-map=/data/builder/debuild/nginx-1.19.0/debian/debuild-base/nginx-1.19.0=. -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC'
#--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,-as-needed -pie'

## ... compare ... (pagespeed

#-with-cc-opt='-g -O2 -fdebug-prefix-map=/data/builder/debuild/nginx-1.19.0/debian/debuild-base/nginx-1.19.0=. -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC'
#--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,-as-needed -pie'
#--add-module=./src/http/modules/ngx_pagespeed/)

# make && make install
RUN make -j$(( `nproc` + 1 )) \
	&& mkdir -vp /usr/local/nginx \
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


## STAGE - RELEASE PACKAGE ##
FROM alpine:latest
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

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
# install tzdata so users could set the timezones through the environment variables
RUN apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp \
	&& apk add --no-cache --virtual .nginx-rundeps $( \
		scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst	\
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
			| xargs \
		) tzdata ca-certificates \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/local/bin/

# remove nginx.conf for future mounting:
# update chmod for nginx ssl dir
# forward request and error logs to docker log collector
RUN rm -vf /etc/nginx/nginx.conf \
	&& chown root:root /etc/nginx/ssl \
	&& chmod 0100 /etc/nginx/ssl \
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]

##
#	# Bring in gettext so we can get `envsubst`, then throw
#	# the rest away. To do this, we need to install `gettext`
#	# then move `envsubst` out of the way so `gettext` can
#	# be deleted completely, then move `envsubst` back.
#	&& apk add --no-cache --virtual .gettext gettext \
#	&& mv /usr/bin/envsubst /tmp/ \
#	&& runDeps="$( \
#		scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
#			| tr ',' '\n' \
#			| sort -u \
#			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
#	)" \
#	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
#	&& apk del .build-deps \
#	&& apk del .gettext
##
# version from `nginx-modules/docker-nginx-boringssl`
#	&& runDeps="$( \
#		scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
#			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
#			| sort -u \
#			| xargs -r apk info --installed \
#			| sort -u \
#	) tzdata ca-certificates"
##
