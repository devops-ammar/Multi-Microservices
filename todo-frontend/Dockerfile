# Stage 1: Builder
FROM node:20-alpine AS builder

WORKDIR /app

# Set the API base URL for production (relative path)
ARG VITE_BACKEND_URL=/api
ENV VITE_BACKEND_URL=$VITE_BACKEND_URL

COPY package*.json ./

RUN npm ci --legacy-peer-deps

COPY . .

RUN npm run build

# Stage 2: Production
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

RUN rm -rf ./*

COPY --from=builder ./app/dist .

# hadolint ignore=DL3018
RUN apk add --no-cache curl

HEALTHCHECK --retries=3 --timeout=5s --interval=30s --start-period=10s \
  CMD curl -f http://localhost/ || exit 1;

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
