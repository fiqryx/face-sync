# =====================================================================
# STAGE 1: DOWNLOADER (Streaming Extractor via Memory Pipe)
# =====================================================================
FROM alpine:latest AS downloader

RUN apk add --no-cache curl jq

WORKDIR /download

ENV JSON_URL="https://raw.githubusercontent.com/fiqryx/face-sync-updater/main/version.json"

RUN echo "[BUILD] Extracting latest .tar.gz releases directly from GitHub..." \
    && curl -s "$JSON_URL" > version.json \
    \
    && mkdir -p bin \
    && BACKEND_URL=$(jq -r '.backend.download_url' version.json) \
    && curl -L "$BACKEND_URL" | tar -xz -C ./bin \
    \
    && WORKER_URL=$(jq -r '.worker.download_url' version.json) \
    && curl -L "$WORKER_URL" | tar -xz -C ./bin \
    \
    && mkdir -p webui \
    && WEBUI_URL=$(jq -r '.webui.download_url' version.json) \
    && curl -L "$WEBUI_URL" | tar -xz -C ./webui

FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    libgomp1 \
    supervisor \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=downloader /download/bin /app/bin
COPY --from=downloader /download/webui /app/webui

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]