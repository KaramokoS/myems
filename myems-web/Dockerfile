FROM node:22-alpine AS build-stage
WORKDIR /opt

# Copy package files first to leverage Docker layer caching
COPY package.json package-lock.json* ./

# Configure npm timeouts to prevent ECONNRESET and install with legacy-peer-deps
RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm install --legacy-peer-deps --no-audit --no-fund

# Copy source and build
COPY . .
RUN npm run build

FROM nginx:alpine AS production-stage

# Remove default config and create web root
RUN rm -f /etc/nginx/conf.d/default.conf && \
    rm -f /etc/nginx/nginx.conf && \
    mkdir -p /var/www/myems-web

COPY nginx.conf /etc/nginx/
COPY --from=build-stage /opt/build/ /var/www/myems-web
EXPOSE 80
CMD ["nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]