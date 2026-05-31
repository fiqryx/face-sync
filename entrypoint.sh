#!/bin/bash

echo "[BOOT] Starting Face-Sync initialization..."
sleep 3

echo "[BOOT] Running database migrations..."
./backend migrate

FLAG_FILE="/app/flag/seeded.flag"
if [ ! -f "$FLAG_FILE" ]; then
    ./backend generate:key
    echo "[BOOT] [FIRST RUN] Fresh environment detected. Running full database seeding..."
    ./backend db:seed
    touch "$FLAG_FILE"
    echo "[BOOT] Seeding completed. Flag file created."
else
    echo "[BOOT] [REBOOT DETECTED] Server/Container just restarted. Skipping seeding safely..."
fi

echo "[BOOT] System is secure! Starting all services via Supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf