#!/bin/bash

echo "[BOOT] Starting Face-Sync initialization..."

# Beri jeda agar PostgreSQL dan Redis benar-benar siap menerima koneksi
sleep 3

# 1. Jalankan Migrasi Database
# (Biasanya aman dijalankan berkali-kali karena ORM Go otomatis skip jika tidak ada perubahan skema)
echo "[BOOT] Running database migrations..."
./backend migrate

# 2. Proteksi Ganda untuk Seeding Database
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

# =====================================================================
# 3. Jalankan Supervisor
# =====================================================================
echo "[BOOT] System is secure! Starting all services via Supervisor..."

# Menggunakan 'exec' agar Supervisor menjadi proses utama (PID 1) di dalam kontainer
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf