#### compile options
```
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
```

#### lib scan from official Dockerfiles

```
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
```
