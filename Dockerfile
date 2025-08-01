# Use your optimized nginx image from Harbor (always updated)
FROM nginx:alpine

LABEL maintainer="kousha ghodsizad"
LABEL build.timestamp="BUILD_TIMESTAMP_PLACEHOLDER"

# Copy your application files
COPY . /usr/share/nginx/html

# Copy your custom nginx configuration
COPY default.conf /etc/nginx/conf.d/default.conf

# Ensure proper permissions
RUN chown -R nginx:nginx /usr/share/nginx/html

# Health check specific to your application
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
