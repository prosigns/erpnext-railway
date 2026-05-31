FROM frappe-image AS assets

# Copy files, follows symlinks and copies real files
RUN cp -rL /home/frappe/frappe-bench/assets /home/frappe/assets

FROM nginx:latest

COPY --from=assets /home/frappe/assets /usr/share/nginx/assets
COPY ./nginx.conf.template /etc/nginx/templates/default.conf.template