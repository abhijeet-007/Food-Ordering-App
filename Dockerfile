# ── Stage 1: test ─────────────────────────────────────────────────────────
FROM node:20-alpine AS test

WORKDIR /app
COPY app/ .

# Verify required files exist
RUN test -f index.html && test -f css/style.css && test -f js/app.js && echo "All files present"

# ── Stage 2: production ────────────────────────────────────────────────────
FROM nginx:1.27-alpine AS production

# Remove default nginx config and content
RUN rm /etc/nginx/conf.d/default.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/app.conf

# Copy static site
COPY app/ /usr/share/nginx/html/

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup && \
    chown -R appuser:appgroup /usr/share/nginx/html && \
    chown -R appuser:appgroup /var/cache/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown appuser:appgroup /var/run/nginx.pid

USER appuser

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
