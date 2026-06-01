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

ENV LOCAL=true
ENV JSON_URL="https://raw.githubusercontent.com/fiqryx/face-sync-updater/main/version.json"

COPY version.json .
COPY build* ./build/

RUN mkdir -p backend_out worker_out webui_out && \
    FETCH_FROM_REMOTE="false" && \
    \
    if [ "$LOCAL" = "true" ]; then \
    echo "LOG: LOCAL mode is enabled. Checking local ./build/ directory..."; \
    \
    BACKEND_FILE=$(basename "$(jq -r '.backend.download_url' version.json)") && \
    WORKER_FILE=$(basename "$(jq -r '.worker.download_url' version.json)") && \
    UPDATER_FILE=$(basename "$(jq -r '.updater.download_url' version.json)") && \
    WEBUI_FILE=$(basename "$(jq -r '.webui.download_url' version.json)") && \
    \
    if [ -f "./build/$BACKEND_FILE" ] && \
    [ -f "./build/$WORKER_FILE" ] && \
    [ -f "./build/$UPDATER_FILE" ] && \
    [ -f "./build/$WEBUI_FILE" ]; then \
    \
    echo "LOG: All local files found. Extracting from ./build/..." && \
    tar -xzf "./build/$BACKEND_FILE" -C ./backend_out && \
    tar -xzf "./build/$WORKER_FILE" -C ./worker_out && \
    tar -xzf "./build/$UPDATER_FILE" -C ./backend_out && \
    tar -xzf "./build/$WEBUI_FILE" -C ./webui_out; \
    else \
    echo "LOG: Some .tar.gz files are missing in ./build/. Falling back to remote download..."; \
    FETCH_FROM_REMOTE="true"; \
    fi; \
    else \
    FETCH_FROM_REMOTE="true"; \
    fi && \
    \
    if [ "$FETCH_FROM_REMOTE" = "true" ]; then \
    echo "LOG: Fetching files from remote URL..."; \
    curl -s "$JSON_URL" > version.json && \
    \
    # Read the LATEST URLs from the freshly downloaded json
    BACKEND_URL=$(jq -r '.backend.download_url' version.json) && \
    WORKER_URL=$(jq -r '.worker.download_url' version.json) && \
    UPDATER_URL=$(jq -r '.updater.download_url' version.json) && \
    WEBUI_URL=$(jq -r '.webui.download_url' version.json) && \
    \
    curl -L "$BACKEND_URL" | tar -xz -C ./backend_out && \
    curl -L "$WORKER_URL" | tar -xz -C ./worker_out && \
    curl -L "$UPDATER_URL" | tar -xz -C ./backend_out && \
    curl -L "$WEBUI_URL" | tar -xz -C ./webui_out; \
    fi && \
    \
    # Cleanup local build directory to keep image size small
    rm -rf ./build

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
RUN pip3 install ./dist/piper_tts-*linux*.whl flask && rm -rf ./dist

COPY .env .
COPY ./local_version.json ./version.json

COPY --from=downloader /download/backend_out/ .
COPY --from=downloader /download/worker_out/ .
COPY --from=downloader /download/webui_out/ ./webui

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh .

RUN chmod +x backend updater main.bin \
    && sed -i 's/\r$//' entrypoint.sh \
    && chmod +x entrypoint.sh

EXPOSE 8000 3000

ENTRYPOINT ["./entrypoint.sh"]