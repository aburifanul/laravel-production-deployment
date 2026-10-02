#!/usr/bin/env bash

# Deploy / update aplikasi Laravel di server Podman
set -euo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " Laravel Production Deployment"
echo "========================================"
echo

# ========================================
# Git
# ========================================

echo "[1/5] Mengambil update dari Git..."

git pull origin main

echo


# ========================================
# Frontend
# ========================================

echo "========================================"
echo " Frontend"
echo "========================================"
echo
echo "Apakah project menggunakan Node.js / Vite?"
echo
echo "  1) Ya, jalankan npm ci && npm run build"
echo "  2) Tidak, lewati build frontend"
echo

read -rp "Pilih [1/2]: " USE_NODE

case "$USE_NODE" in
    1)
        if [ ! -f package.json ]; then
            echo
            echo "ERROR: package.json tidak ditemukan."
            echo "Project tidak dapat menjalankan build Node/Vite."
            exit 1
        fi

        echo
        echo "Menjalankan build frontend..."

        podman run --rm \
            -v "$PWD:/app:Z" \
            -w /app \
            docker.io/library/node:24-alpine \
            sh -c "npm ci && npm run build"

        echo "Build frontend selesai."
        ;;

    2)
        echo
        echo "Build frontend dilewati."
        ;;

    *)
        echo
        echo "ERROR: Pilihan tidak valid."
        echo "Gunakan 1 atau 2."
        exit 1
        ;;
esac

echo


# ========================================
# Build & Start Container
# ========================================

echo "========================================"
echo " Container"
echo "========================================"

echo
echo "Membangun image..."

podman compose build

echo
echo "Menjalankan container..."

podman compose up -d

echo


# ========================================
# Get App Container
# ========================================

echo "Mencari container service 'app'..."

CONTAINER_NAME="$(
    podman ps \
        --filter "label=com.docker.compose.service=app" \
        --format "{{.Names}}" \
        | head -n 1
)"

if [ -z "$CONTAINER_NAME" ]; then
    echo "ERROR: Container service 'app' tidak ditemukan."
    echo
    echo "Container yang sedang berjalan:"
    podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    exit 1
fi

echo "Container aplikasi:"
echo "$CONTAINER_NAME"

echo


# ========================================
# Wait for Container
# ========================================

echo "Menunggu container aplikasi siap..."

sleep 5

if [ "$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}')" != "running" ]; then
    echo "ERROR: Container '$CONTAINER_NAME' tidak berjalan."
    echo
    echo "Status container:"
    podman ps -a --filter "name=^${CONTAINER_NAME}$"
    echo
    echo "Log container:"
    podman logs --tail 50 "$CONTAINER_NAME"
    exit 1
fi

echo "Container aplikasi siap."

echo


# ========================================
# Composer
# ========================================

echo "========================================"
echo " Composer"
echo "========================================"

echo
echo "Menginstal dependency PHP (production)..."

podman exec "$CONTAINER_NAME" \
    composer install --no-dev --optimize-autoloader --no-interaction

echo


# ========================================
# Laravel
# ========================================

echo "========================================"
echo " Laravel"
echo "========================================"

echo
echo "Menjalankan database migration..."

podman exec "$CONTAINER_NAME" \
    php artisan migrate --force

echo
echo "Membersihkan cache Laravel..."

podman exec "$CONTAINER_NAME" \
    php artisan optimize:clear

echo
echo "Membuat cache production..."

podman exec "$CONTAINER_NAME" \
    php artisan optimize

echo


# ========================================
# Finish
# ========================================

echo "========================================"
echo " Deployment selesai."
echo "========================================"