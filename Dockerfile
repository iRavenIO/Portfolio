FROM node:18-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . ./
RUN npm run build

FROM node:18-alpine

LABEL maintainer="kousha ghodsizad"
LABEL build.timestamp="BUILD_TIMESTAMP_PLACEHOLDER"

RUN apk add --no-cache nginx curl

WORKDIR /app

COPY default.conf /etc/nginx/http.d/default.conf
COPY --from=builder /app/out /usr/share/nginx/html
COPY --from=builder /app/node_modules /app/node_modules
COPY --from=builder /app/package.json /app/package.json
COPY --from=builder /app/services/admin-api /app/services/admin-api
COPY --from=builder /app/content /app/content
COPY scripts/start-portfolio-runtime.sh /app/scripts/start-portfolio-runtime.sh

RUN mkdir -p /run/nginx /var/lib/nginx/logs /app/services/admin-api/data \
    && chmod +x /app/scripts/start-portfolio-runtime.sh \
    && chown -R nginx:nginx /usr/share/nginx/html /run/nginx /var/lib/nginx /app/services/admin-api/data

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

CMD ["/app/scripts/start-portfolio-runtime.sh"]
