# =====================================================================
# STAGE 1: Pinjam Builder Resmi Milik Piper untuk Membuat Modul Python
# =====================================================================
FROM python:3.12 AS piper-builder
RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
    build-essential cmake ninja-build git

WORKDIR /app
RUN git clone --depth 1 --branch v1.4.2 https://github.com/OHF-Voice/piper1-gpl.git .
RUN script/setup --dev
RUN script/dev_build
RUN script/package

# =====================================================================
# STAGE 2: DOWNLOADER AUTOMATION (Streaming Extractor via Memory Pipe)
# =====================================================================
FROM alpine:latest AS downloader
RUN apk add --no-cache curl jq

WORKDIR /download
ENV JSON_URL="https://raw.githubusercontent.com/fiqryx/face-sync-updater/main/version.json"

RUN curl -s "$JSON_URL" > version.json \
    && mkdir -p backend_out worker_out webui_out \

    && BACKEND_URL=$(jq -r '.backend.download_url' version.json) \
    && curl -L "$BACKEND_URL" | tar -xz -C ./backend_out \

    && WORKER_URL=$(jq -r '.worker.download_url' version.json) \
    && curl -L "$WORKER_URL" | tar -xz -C ./worker_out \

    && UPDATER_URL=$(jq -r '.updater.download_url' version.json) \
    && curl -L "$UPDATER_URL" | tar -xz -C ./backend_out \

    && WEBUI_URL=$(jq -r '.webui.download_url' version.json) \
    && curl -L "$WEBUI_URL" | tar -xz -C ./webui_out

FROM python:3.12-slim
WORKDIR /app

ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    supervisor \
    curl \
    libgomp1 \
    sed \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

COPY --from=piper-builder /app/dist/piper_tts-*linux*.whl ./dist/
RUN pip3 install ./dist/piper_tts-*linux*.whl && rm -rf ./dist

COPY .env .
COPY .local_version.json ./version.json

COPY --from=downloader /download/backend_out/ .
COPY --from=downloader /download/worker_out/ .
COPY --from=downloader /download/webui_out/webui ./webui

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh .

RUN chmod +x backend updater main.bin \
    && sed -i 's/\r$//' entrypoint.sh \
    && chmod +x entrypoint.sh

EXPOSE 8000 3000

ENTRYPOINT ["./entrypoint.sh"]