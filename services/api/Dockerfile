# Build the modular-monolith API from the repository root so the image can
# carry the versioned SQL migrations used by the deployment migration runner.
FROM golang:1.23-alpine AS build

RUN apk add --no-cache ca-certificates git
WORKDIR /src/services/api
COPY services/api/go.mod services/api/go.sum ./
RUN go mod download
COPY services/api/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/nidaw-api ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata bash postgresql-client \
    && addgroup -S -g 10001 nidaw \
    && adduser -S -D -H -u 10001 -G nidaw nidaw
COPY --from=build --chown=10001:10001 /out/nidaw-api /usr/local/bin/nidaw-api
COPY --chown=10001:10001 scripts/migrations/migrate-up.sh /usr/local/bin/migrate-up.sh
COPY --chown=10001:10001 data/migrations/postgres /opt/nidaw/migrations/postgres
RUN chmod 0555 /usr/local/bin/nidaw-api /usr/local/bin/migrate-up.sh \
    && chmod -R a=rX /opt/nidaw/migrations
USER 10001:10001
EXPOSE 8080
ENV SERVER_HOST=0.0.0.0 SERVER_PORT=8080 ENVIRONMENT=production
ENTRYPOINT ["/usr/local/bin/nidaw-api"]
