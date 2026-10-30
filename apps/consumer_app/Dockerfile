# Compile the Flutter consumer application for web.
FROM ghcr.io/cirruslabs/flutter:3.24.0 AS build
WORKDIR /src
COPY pubspec.yaml ./
RUN flutter pub get
COPY . .
ARG API_BASE_URL=https://api.nidaw.com
ARG WS_BASE_URL=wss://api.nidaw.com/ws
ARG ENVIRONMENT=production
RUN flutter build web --release \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=WS_BASE_URL=${WS_BASE_URL} \
    --dart-define=ENVIRONMENT=${ENVIRONMENT}

# Nginx listens on 8080 so it can run without root in Kubernetes.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 8080
