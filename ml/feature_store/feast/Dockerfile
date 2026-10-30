FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 feast \
    && useradd --system --uid 10001 --gid feast --home-dir /app feast

WORKDIR /app
RUN pip install --no-cache-dir "feast[redis]==0.37.0"
COPY --chown=10001:10001 feature_repo ./feature_repo
WORKDIR /app/feature_repo
USER 10001:10001
EXPOSE 6566
CMD ["feast", "serve", "--host", "0.0.0.0", "--port", "6566"]
