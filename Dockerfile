# custom nginx by vkom
FROM alpine:3.8 as builder

LABEL maintainer="vkom <admin@mh00p.net>"

ARG IN_NGINX_VERSION=1.16.0
ARG IN_NGXMOD_GRAPHITE_VERSION=2.0
ARG IN_NGXMOD_TSTCK_VERSION=master
ARG IN_NGXMOD_PAM_VERSION=1.5.1
ARG IN_NGXMOD_NAXSI_VERSION=0.55.3

ENV NGINX_VERSION=$IN_NGINX_VERSION
ENV NGXMOD_GRAPHITE_VERSION=$IN_NGXMOD_GRAPHITE_VERSION
ENV NGXMOD_TSTCK_VERSION=$IN_NGXMOD_TSTCK_VERSION
ENV NGXMOD_PAM_VERSION=$IN_NGXMOD_PAM_VERSION
ENV NGXMOD_NAXSI_VERSION=$IN_NGXMOD_NAXSI_VERSION

# install build dependencies
RUN apk add --no-cache build-base curl gnupg1 linux-headers \
		libc-dev openssl-dev pcre-dev zlib-dev libxslt-dev gd-dev geoip-dev linux-pam-dev

# create builddir
RUN mkdir -p /usr/src/nginx \
	&& mkdir -p /usr/local/nginx
WORKDIR /usr/src/nginx

# download nginx & nginx modules
RUN curl -f -sS -L https://nginx.org/download/nginx-{$NGINX_VERSION}.tar.gz | tar zxC .
RUN curl -f -sS -L https://github.com/mailru/graphite-nginx-module/archive/v${NGXMOD_GRAPHITE_VERSION}.tar.gz | tar zxC .
RUN curl -f -sS -L https://github.com/kyprizel/testcookie-nginx-module/archive/${NGXMOD_TSTCK_VERSION}.tar.gz | tar zxC .
RUN curl -f -sS -L https://github.com/nbs-system/naxsi/archive/${NGXMOD_NAXSI_VERSION}.tar.gz | tar zxC .
RUN curl -f -sS -L https://github.com/sto/ngx_http_auth_pam_module/archive/v${NGXMOD_PAM_VERSION}.tar.gz | tar zxC .

# patch nginx sources && configure
WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}
RUN patch -p1 < ../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION}/graphite_module_v1_7_7.patch
RUN ./configure \
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
		--with-pcre \
		--with-pcre-jit \
		--without-select_module \
		--without-poll_module \
		--without-http_ssi_module \
		--without-http_auth_basic_module \
		--without-http_split_clients_module \
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
		--with-http_sub_module \
		--with-http_secure_link_module\
		--with-http_stub_status_module \
		--with-http_dav_module \
		--with-http_realip_module \
		--with-http_addition_module \
		--with-stream=dynamic \
		--with-http_xslt_module=dynamic \
		--with-http_image_filter_module=dynamic \
		--with-http_geoip_module=dynamic \
		--add-dynamic-module=../ngx_http_auth_pam_module-${NGXMOD_PAM_VERSION} \
		--add-module=../graphite-nginx-module-${NGXMOD_GRAPHITE_VERSION} \
		--add-module=../testcookie-nginx-module-${NGXMOD_TSTCK_VERSION} \
		--add-module=../naxsi-${NGXMOD_NAXSI_VERSION}/naxsi_src \
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
FROM alpine:3.8

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
#	&& mv /tmp/envsubst /usr/local/bin/ \

