FROM nginx:alpine

# Replace the default nginx site config with one that listens on 8080
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

# Copy the static game files
COPY app/ /usr/share/nginx/html/

# Entrypoint script injects the VM's hostname into config.js at container start
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
