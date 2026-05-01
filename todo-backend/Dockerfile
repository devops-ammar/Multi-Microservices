# Stage 1: Builder
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci

# Stage 2: Production
FROM node:20-alpine

WORKDIR /app

RUN addgroup -S nodejs -g 5150 && adduser -S nodejs  -u 5151 nodejs

COPY --from=builder --chown=nodejs:nodejs ./app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .

RUN apk add --no-cache tini=0.19.0-r0 curl=8.9.1-r0

HEALTHCHECK --retries=3 --interval=30s --timeout=5s --start-period=10s \
    CMD curl -f http://localhost:3000/health || exit 1

USER nodejs

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]

CMD ["node", "bin/www"]
