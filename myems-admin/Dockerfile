FROM nginx:alpine

# Remove default config and create admin root
RUN rm -f /etc/nginx/conf.d/default.conf && \
    rm -f /etc/nginx/nginx.conf && \
    mkdir -p /var/www/myems-admin

# Copy nginx config and static assets
COPY nginx.conf /etc/nginx/
COPY . /var/www/myems-admin
EXPOSE 8001
CMD ["nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]