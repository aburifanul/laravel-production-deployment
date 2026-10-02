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
echo

git pull origin main

echo


# ========================================
# Frontend
# ========================================

echo "========================================"
echo " Frontend"
echo "========================================"
echo

USE_NODE=""

for ARG in "$@"; do
    case "$ARG" in
        --with-node)
            USE_NODE="1"
            ;;
        --skip-node)
            USE_NODE="2"
            ;;
        *)
            echo "ERROR: Argumen tidak dikenal: $ARG"
            echo
            echo "Penggunaan:"
            echo "  bash scripts/deploy.sh"
            echo "  bash scripts/deploy.sh --with-node"
            echo "  bash scripts/deploy.sh --skip-node"
            exit 1
            ;;
    esac
done

if [ -z "$USE_NODE" ]; then
    echo "Apakah project menggunakan Node.js / Vite?"
    echo
    echo "  1) Ya, jalankan npm ci && npm run build"
    echo "  2) Tidak, lewati build frontend"
    echo
    read -rp "Pilih [1/2]: " USE_NODE
fi

case "$USE_NODE" in
    1)
        if [ ! -f package.json ]; then
            echo
            echo "ERROR: package.json tidak ditemukan."
            echo "Tidak dapat menjalankan build frontend."
            exit 1
        fi

        echo
        echo "Menjalankan build frontend..."
        echo

        podman run --rm \
            -v "$PWD:/app:Z" \
            -w /app \
            docker.io/library/node:24-alpine \
            sh -c "npm ci && npm run build"

        echo
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
# Find Existing App Container
# ========================================

echo "========================================"
echo " Container"
echo "========================================"
echo

echo "Mencari container service 'app'..."

OLD_CONTAINER="$(podman ps -aq --filter "label=com.docker.compose.service=app" | head -n 1)"

if [ -n "$OLD_CONTAINER" ]; then

    OLD_CONTAINER_NAME="$(podman inspect "$OLD_CONTAINER" --format '{{.Name}}' | sed 's#^/##')"

    echo "Container lama ditemukan:"
    echo "$OLD_CONTAINER_NAME"
    echo

    echo "Menghapus container lama..."

    podman rm -f "$OLD_CONTAINER" >/dev/null

    echo "Container lama berhasil dihapus."
else
    echo "Tidak ada container lama."
fi

echo


# ========================================
# Build Image
# ========================================

echo "Membangun image aplikasi..."
echo

BUILDAH_FORMAT=docker podman compose build

echo
echo "Image berhasil dibuat."
echo


# ========================================
# Start Container
# ========================================

echo "Menjalankan container aplikasi..."
echo

podman compose up -d

echo


# ========================================
# Get New App Container
# ========================================

echo "Mencari container service 'app'..."

CONTAINER_NAME="$(podman ps --filter "label=com.docker.compose.service=app" --format "{{.Names}}" | head -n 1)"

if [ -z "$CONTAINER_NAME" ]; then

    echo
    echo "ERROR: Container service 'app' tidak ditemukan."
    echo

    echo "Container yang tersedia:"
    podman ps -a \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

    exit 1
fi

echo
echo "Container aplikasi:"
echo "$CONTAINER_NAME"
echo


# ========================================
# Wait for Container
# ========================================

echo "Menunggu container aplikasi siap..."

for i in {1..30}; do

    STATUS="$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || true)"

    if [ "$STATUS" = "running" ]; then
        break
    fi

    if [ "$STATUS" = "exited" ] || [ "$STATUS" = "dead" ]; then

        echo
        echo "ERROR: Container '$CONTAINER_NAME' berhenti."
        echo

        echo "Status container:"
        podman ps -a \
            --filter "name=^${CONTAINER_NAME}$"

        echo
        echo "Log container:"
        podman logs --tail 100 "$CONTAINER_NAME"

        exit 1
    fi

    sleep 1
done

STATUS="$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}')"

if [ "$STATUS" != "running" ]; then

    echo
    echo "ERROR: Container '$CONTAINER_NAME' tidak berjalan."
    echo

    echo "Status container:"
    podman ps -a \
        --filter "name=^${CONTAINER_NAME}$"

    echo
    echo "Log container:"
    podman logs --tail 100 "$CONTAINER_NAME"

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

echo "Menginstal dependency PHP production..."

podman exec "$CONTAINER_NAME" \
    composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

echo
echo "Composer selesai."
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
echo "Migration selesai."
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
# Final Check
# ========================================

echo "========================================"
echo " Deployment Check"
echo "========================================"
echo

FINAL_STATUS="$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}')"

if [ "$FINAL_STATUS" != "running" ]; then
    echo "ERROR: Container berhenti setelah deployment."
    exit 1
fi

echo "Container : $CONTAINER_NAME"
echo "Status    : $FINAL_STATUS"
echo

echo "========================================"
echo " Deployment selesai."
echo "========================================"
