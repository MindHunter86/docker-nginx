# custom nginx by vkom

## STAGE - BORINGSSL BUILD ##
FROM alpine:latest as sslbuilder
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache git curl gnupg build-base cmake linux-headers perl libunwind-dev go

# https://trac.nginx.org/nginx/ticket/2605
#
# just as note, using the "latest" version of BoringSSL, TLS v1.2 is not more available in nginx and nginx works only with TLS 1.3

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

ARG TARGETPLATFORM

ARG IN_NGINX_VERSION=1.26.0
# ARG IN_NGXMOD_GRAPHITE_VERSION=master # v3.1
ARG IN_NGXMOD_HEADMR_VERSION=master
ARG IN_NGXMOD_VTS_VERSION=0.2.2

ENV NGINX_VERSION=$IN_NGINX_VERSION
# ENV NGXMOD_GRAPHITE_VERSION=$IN_NGXMOD_GRAPHITE_VERSION
ENV NGXMOD_HEADMR_VERSION=$IN_NGXMOD_HEADMR_VERSION
ENV NGXMOD_VTS_VERSION=$IN_NGXMOD_VTS_VERSION

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

WORKDIR /usr/src/nginx
COPY --from=sslbuilder /usr/src/boringssl ./boringssl

# download nginx & nginx modules
# AND
# - Add HTTP2 HPACK Encoding Support
# 	* Since Nginx 1.25.1, HPACK encoding will not support because the HTTP/2 server push support has been removed
# - Add Dynamic TLS Record Support
# - For BoringSSL support OCSP stapling
# https://raw.githubusercontent.com/kn007/patch/master/nginx_for_1.23.4.patch
# https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.17.7%2B.patch
RUN apk add --no-cache curl \
	&& curl -f -sS -L https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/openresty/headers-more-nginx-module/archive/${NGXMOD_HEADMR_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://github.com/vozlt/nginx-module-vts/archive/v${NGXMOD_VTS_VERSION}.tar.gz | tar zxC . \
	&& curl -f -sS -L https://raw.githubusercontent.com/kn007/patch/master/nginx_dynamic_tls_records.patch -o nginx_dynamic_tls_records.patch \
	&& curl -f -sS -L https://raw.githubusercontent.com/kn007/patch/master/Enable_BoringSSL_OCSP.patch -o Enable_BoringSSL_OCSP.patch

	# && curl -f -sS -L https://github.com/mailru/graphite-nginx-module/archive/${NGXMOD_GRAPHITE_VERSION}.tar.gz | tar zxC . \
	# && patch -p1 < ../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION}/graphite_module_v1_15_4.patch \
	# && patch -p1 < ../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION}/nginx_error_log_limiting_v1_15.4.patch \
	# --add-module=../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION} \

# ls debug
# && ls -lah /usr/src/nginx ||: \
# && ls -lah ../boringssl ||: \
# && ls -lah ../boringssl/.openssl/lib/ ||: \

# install build dependencies
# patch nginx sources && configure
WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}
RUN echo "ready" \
	&& apk add --no-cache build-base git gnupg linux-headers \
	libc-dev pcre-dev pcre2-dev zlib-dev libxslt-dev gd-dev geoip-dev libaio libaio-dev \
	&& echo "patching nginx_dynamic_tls_records.patch ..." \
	&& patch -p1 < ../nginx_dynamic_tls_records.patch \
	&& echo "patching Enable_BoringSSL_OCSP.patch ..." \
	&& patch -p1 < ../Enable_BoringSSL_OCSP.patch \
	&& if [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCH_CC=""; else ARCH_CC="-m64"; fi \
	&& echo "running on ${TARGETPLATFORM} so cc falgs - ${ARCH_CC}" > /dev/stderr \
	&& echo "running on ${TARGETPLATFORM} so cc falgs - ${ARCH_CC}" > /dev/stderr \
	&& ./configure --help ||: \
	&& ./configure \
	--build="Custom with BoringSSL, CF-TLS and BorSSL-OCSP patches for ${TARGETPLATFORM}" \
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
	--add-module=../headers-more-nginx-module-${NGXMOD_HEADMR_VERSION} \
	--add-module=../nginx-module-vts-${NGXMOD_VTS_VERSION} \
	--with-cc=c++ \
	--with-ld-opt='-L ../boringssl/.openssl/lib -Wl,-E -Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,-as-needed -pie' \
	--with-cc-opt='-I ../boringssl/.openssl/include -x c -m64 -O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -mtune=generic'
	# --with-cc-opt="-I /usr/src/nginx/boringssl/.openssl/include/ ${ARCH_CC} -mtune=generic -O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -Wimplicit-fallthrough=0 -Wno-deprecated-declarations -flto -ffat-lto-objects -fexceptions -fstack-protector-strong -fcode-hoisting -fPIC --param=ssp-buffer-size=4 -gsplit-dwarf -DTCP_FASTOPEN=23"

# -march=native -mtune=native
# hetzner kaby lake march - '-march=skylake -O2 -pipe'
# hetzner amd apic - '-march=znver1 -mtune=znver1 -mfma -mavx2 -m3dnow -fomit-frame-pointer'

# gcc options manual from redhat
# https://developers.redhat.com/blog/2018/03/21/compiler-and-linker-flags-gcc

# ? to delete (the backup):
# --with-cc-opt='-I /usr/src/nginx/boringssl/.openssl/include/ -O3 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic'

# debian apt repo
#--with-cc-opt='-g -O2 -fdebug-prefix-map=/data/builder/debuild/nginx-1.19.0/debian/debuild-base/nginx-1.19.0=. -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC'
#--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,-as-needed -pie'

# make && make install
RUN make -j$(( `nproc` + 1 )) \
	&& mkdir -vp /usr/local/nginx \
	&& make DESTDIR=/usr/local/nginx install

# mkdir for dynamic modules, configs, ssl, caches
# strip all bins and libs
WORKDIR /usr/local/nginx
RUN mkdir -p usr/lib/nginx/modules \
	&& ln -s ../../usr/lib/nginx/modules etc/nginx/modules \
	&& mkdir etc/nginx/conf.d \
	&& mkdir etc/nginx/ssl \
	&& mkdir -p var/cache/nginx/client_temp \
	&& mkdir -p var/cache/nginx/proxy_temp \
	&& mkdir -p var/cache/nginx/fastcgi_temp \
	&& strip usr/sbin/nginx* \
	&& strip usr/lib/nginx/modules/*so \
	&& tar c . -f ../nginx.rootfs.tar


## STAGE - RELEASE PACKAGE ##
FROM alpine:latest
LABEL maintainer="mindhunter86 <mindhunter86@vkom.cc>"

# hadolint/hadolint - DL4006
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# github.com/moby/moby/issues/25925
# COPY --from=builder /usr/local/nginx/ /
COPY --from=builder /usr/local/nginx.rootfs.tar /
RUN tar xvC / -f /nginx.rootfs.tar \
	&& rm -vf /nginx.rootfs.tar

# install run dependencies
# install tzdata so users could set the timezones through the environment variables
RUN apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp \
	&& apk add --no-cache \
		$(scanelf --needed --nobanner /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
		) tzdata ca-certificates \
	&& mv -v /tmp/envsubst /usr/local/bin/ \
	&& apk del .gettext

# user & group management
# remove nginx.conf for future mounting:
# update chmod for nginx ssl dir
# forward request and error logs to docker log collector
RUN addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& rm -vf /etc/nginx/nginx.conf \
	&& chown -v root:root /etc/nginx/ssl \
	&& chmod -v go-rwx /etc/nginx/ssl \
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80
STOPSIGNAL SIGTERM

ENTRYPOINT [ "/usr/sbin/nginx" ]
CMD [ "-g", "daemon off;" ]

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
