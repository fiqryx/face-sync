#!/bin/bash

echo "[BOOT] Starting Face-Sync initialization..."
sleep 3

echo "[BOOT] Sync database..."
./backend migrate

FLAG_FILE="/app/flag/seeded.flag"
if [ ! -f "$FLAG_FILE" ]; then
    ./backend generate:key
    echo "[BOOT] Fresh environment detected. Running setup environment..."
    ./backend db:seed
    touch "$FLAG_FILE"
    echo "[BOOT] Setup completed. Flag file created."
fi

echo "[BOOT] System is secure! Starting all services via Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf