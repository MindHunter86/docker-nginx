# docker-nginx
Custom nginx with modules naxsi, graphite, pam_auth, testcookie in docker

WARNING:
some dirs and files must be "bind" mounted:
- /etc/nginx/nginx.conf
- /etc/nginx/ssl

Dockerfile originally from nginxinc/docker-nginx
