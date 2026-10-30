# ============================================================================
# NIDAW Driver App - Flutter Web Build
# ============================================================================

FROM ghcr.io/cirruslabs/flutter:3.16.5 AS builder

WORKDIR /app

ARG API_BASE_URL=https://api.nidaw.com
ARG WS_BASE_URL=wss://api.nidaw.com/ws
ARG ENVIRONMENT=production

# This app does not check in a pubspec.lock; resolve dependencies from pubspec.yaml.
COPY pubspec.yaml ./
RUN flutter pub get

# Copy source code
COPY . .

# Build for web
RUN flutter build web \
    --release \
    --dart-define=API_BASE_URL=${API_BASE_URL:-https://api.nidaw.com} \
    --dart-define=WS_BASE_URL=${WS_BASE_URL:-wss://api.nidaw.com/ws} \
    --dart-define=ENVIRONMENT=${ENVIRONMENT:-production}

# ============================================================================
# Runtime Stage
# ============================================================================
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]