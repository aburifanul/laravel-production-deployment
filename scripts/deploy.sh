#!/usr/bin/env bash

# Deploy / update aplikasi Laravel di server Podman
set -Eeuo pipefail

cd "$(dirname "$0")/.."

echo "========================================"
echo " Laravel Production Deployment"
echo "========================================"
echo

# ========================================
# Configuration
# ========================================

CONTAINER_NAME=""
APP_PORT=""

# Bisa diubah dari luar, contoh: HEALTH_URL=http://127.0.0.1:8000/up bash scripts/deploy.sh
HEALTH_URL="${HEALTH_URL:-}"

OLD_CONTAINER=""
OLD_CONTAINER_NAME=""
NEW_CONTAINER_NAME=""
NEW_IMAGE=""
ROLLBACK_IMAGE=""
DEPLOYMENT_STARTED=0
CONTAINER_REPLACED=0

# Membaca nilai dari .env (komentar inline dan tanda kutip diabaikan)
env_value() {
    local key="$1"
    local default="${2:-}"
    local value

    value="$(grep -E "^${key}=" .env | tail -n 1 | cut -d= -f2- || true)"

    value="$(
        printf '%s' "$value" | sed -E \
            -e 's/[[:space:]]+#.*$//' \
            -e 's/^[[:space:]]+//' \
            -e 's/[[:space:]]+$//' \
            -e 's/^"(.*)"$/\1/' \
            -e "s/^'(.*)'\$/\\1/"
    )"

    printf '%s' "${value:-$default}"
}

# ========================================
# Cleanup / Rollback
# ========================================

rollback() {
    local exit_code=$?

    if [ "$DEPLOYMENT_STARTED" -eq 0 ]; then
        exit "$exit_code"
    fi

    echo
    echo "========================================"
    echo " Deployment gagal"
    echo "========================================"
    echo

    if [ "$CONTAINER_REPLACED" -eq 1 ]; then
        echo "Container baru gagal dalam proses deployment."

        if [ -n "$NEW_CONTAINER_NAME" ]; then
            echo
            echo "Log container baru:"
            podman logs --tail 100 "$NEW_CONTAINER_NAME" 2>/dev/null || true
        fi

        echo

        if [ -n "$ROLLBACK_IMAGE" ]; then
            echo "Image deployment sebelumnya tersedia:"
            echo "$ROLLBACK_IMAGE"
            echo
            echo "Container lama tidak dapat dipulihkan otomatis"
            echo "tanpa mengganggu konfigurasi Compose saat ini."
        fi
    else
        echo "Container production lama belum disentuh."
        echo "Production seharusnya tetap menggunakan container sebelumnya."
    fi

    echo
    echo "Deployment dihentikan."
    echo

    exit "$exit_code"
}

trap rollback ERR

# ========================================
# Pre-flight Check
# ========================================

echo "========================================"
echo " Pre-flight Check"
echo "========================================"
echo

for CMD in podman git curl; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: $CMD tidak ditemukan."
        exit 1
    fi
done

if [ ! -f docker-compose.yml ]; then
    echo "ERROR: docker-compose.yml tidak ditemukan."
    exit 1
fi

if [ ! -f .env ]; then
    echo "ERROR: File .env tidak ditemukan di $PWD."
    echo "Buat dulu dari template: cp .env.example .env"
    exit 1
fi

# Cegah dua deployment berjalan bersamaan di folder yang sama
if command -v flock >/dev/null 2>&1; then
    exec 9<.

    if ! flock -n 9; then
        echo "ERROR: Deployment lain sedang berjalan di $PWD."
        echo "Tunggu sampai selesai, lalu jalankan lagi."
        exit 1
    fi
fi

CONTAINER_NAME="$(env_value CONTAINER_NAME app)"
APP_PORT="$(env_value APP_PORT 8000)"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:${APP_PORT}/}"

echo "Podman    : $(podman --version)"
echo "Git       : $(git --version)"
echo "Project   : $(basename "$PWD")"
echo "Container : $CONTAINER_NAME"
echo "Port      : $APP_PORT"
echo

# ========================================
# Find Existing App Container
# ========================================

echo "========================================"
echo " Current Container"
echo "========================================"
echo

# Container dicari berdasarkan CONTAINER_NAME dari .env (bukan label),
# supaya aman jika satu server menjalankan banyak project.
if podman container exists "$CONTAINER_NAME"; then

    OLD_CONTAINER="$(
        podman inspect "$CONTAINER_NAME" \
            --format '{{.Id}}'
    )"

    OLD_CONTAINER_NAME="$CONTAINER_NAME"

    # Pastikan container ini milik folder project ini, bukan project lain
    # yang kebetulan memakai CONTAINER_NAME yang sama.
    OWNER_DIR="$(
        podman inspect "$OLD_CONTAINER" \
            --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
            2>/dev/null || true
    )"

    if [ -n "$OWNER_DIR" ]; then

        if [ "$(realpath -m "$OWNER_DIR")" != "$(pwd -P)" ]; then
            echo "ERROR: Container '$CONTAINER_NAME' dimiliki project lain."
            echo
            echo "  Folder pemilik : $OWNER_DIR"
            echo "  Folder ini     : $(pwd -P)"
            echo
            echo "Ubah CONTAINER_NAME di .env menjadi nama yang unik,"
            echo "lalu jalankan lagi. Tidak ada container yang disentuh."
            exit 1
        fi

    else
        echo "WARNING: Pemilik container tidak dapat diverifikasi"
        echo "(label com.docker.compose.project.working_dir tidak ada)."
        echo
    fi

    echo "Container production ditemukan:"
    echo "  Name : $OLD_CONTAINER_NAME"
    echo "  ID   : $OLD_CONTAINER"

    OLD_STATUS="$(
        podman inspect "$OLD_CONTAINER" \
            --format '{{.State.Status}}'
    )"

    OLD_IMAGE="$(
        podman inspect "$OLD_CONTAINER" \
            --format '{{.ImageName}}'
    )"

    echo "  Status: $OLD_STATUS"
    echo "  Image : $OLD_IMAGE"
    echo

    if [ "$OLD_STATUS" != "running" ]; then
        echo "WARNING: Container lama tidak sedang running."
        echo
    fi

    ROLLBACK_IMAGE="$OLD_IMAGE"

else

    echo "Tidak ada container production lama."
    echo

fi

# ========================================
# Git
# ========================================

echo "========================================"
echo " Git"
echo "========================================"
echo

echo "Mengambil update dari Git..."
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
# Build Image
# ========================================

echo "========================================"
echo " Build Image"
echo "========================================"
echo

echo "Membangun image aplikasi..."
echo
echo "Container production lama BELUM dihapus."
echo

BUILDAH_FORMAT=docker podman compose build

echo
echo "Image berhasil dibuat."
echo

# ========================================
# Replace Container
# ========================================

echo "========================================"
echo " Replace Container"
echo "========================================"
echo

DEPLOYMENT_STARTED=1

if [ -n "$OLD_CONTAINER" ]; then

    echo "Container lama:"
    echo "$OLD_CONTAINER_NAME"
    echo

    echo "Menghentikan container lama..."

    podman stop "$OLD_CONTAINER" >/dev/null

    echo "Container lama dihentikan."
    echo

    echo "Menghapus container lama..."

    podman rm "$OLD_CONTAINER" >/dev/null

    echo "Container lama berhasil dihapus."
    echo

else

    echo "Tidak ada container lama yang perlu diganti."
    echo

fi

CONTAINER_REPLACED=1

# ========================================
# Start New Container
# ========================================

echo "========================================"
echo " Start Container"
echo "========================================"
echo

echo "Menjalankan container aplikasi..."
echo

podman compose up -d 9>&-

echo

# ========================================
# Get New App Container
# ========================================

echo "Mencari container '${CONTAINER_NAME}'..."

for i in {1..15}; do

    if podman container exists "$CONTAINER_NAME"; then
        break
    fi

    sleep 1

done

if ! podman container exists "$CONTAINER_NAME"; then

    echo
    echo "ERROR: Container '${CONTAINER_NAME}' tidak ditemukan."
    echo

    echo "Container yang tersedia:"
    podman ps -a \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

    exit 1
fi

NEW_CONTAINER_NAME="$CONTAINER_NAME"

NEW_IMAGE="$(
    podman inspect "$NEW_CONTAINER_NAME" \
        --format '{{.ImageName}}'
)"

echo
echo "Container aplikasi:"
echo "$NEW_CONTAINER_NAME"
echo
echo "Image:"
echo "$NEW_IMAGE"
echo

# ========================================
# Wait for Container
# ========================================

echo "Menunggu container aplikasi siap..."

CONTAINER_READY=0

for i in {1..30}; do

    STATUS="$(
        podman inspect "$NEW_CONTAINER_NAME" \
            --format '{{.State.Status}}' \
            2>/dev/null || true
    )"

    case "$STATUS" in

        running)

            CONTAINER_READY=1
            break
            ;;

        exited|dead)

            echo
            echo "ERROR: Container '$NEW_CONTAINER_NAME' berhenti."
            echo

            echo "Status container:"
            podman ps -a \
                --filter "name=^${NEW_CONTAINER_NAME}$"

            echo
            echo "Log container:"
            podman logs --tail 100 "$NEW_CONTAINER_NAME" || true

            exit 1
            ;;

    esac

    sleep 1

done

if [ "$CONTAINER_READY" -ne 1 ]; then

    echo
    echo "ERROR: Container tidak menjadi running dalam 30 detik."
    echo

    echo "Status container:"
    podman ps -a \
        --filter "name=^${NEW_CONTAINER_NAME}$"

    echo
    echo "Log container:"
    podman logs --tail 100 "$NEW_CONTAINER_NAME" || true

    exit 1
fi

echo "Container aplikasi running."
echo

# ========================================
# Composer
# ========================================

echo "========================================"
echo " Composer"
echo "========================================"
echo

echo "Menginstal dependency PHP production..."

podman exec "$NEW_CONTAINER_NAME" \
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

podman exec "$NEW_CONTAINER_NAME" \
    php artisan migrate --force

echo
echo "Migration selesai."
echo

echo "Membersihkan cache Laravel..."

podman exec "$NEW_CONTAINER_NAME" \
    php artisan optimize:clear

echo
echo "Membuat cache production..."

podman exec "$NEW_CONTAINER_NAME" \
    php artisan optimize

echo

# ========================================
# Final Deployment Check
# ========================================

echo "========================================"
echo " Final Deployment Check"
echo "========================================"
echo

FINAL_STATUS="$(
    podman inspect "$NEW_CONTAINER_NAME" \
        --format '{{.State.Status}}'
)"

if [ "$FINAL_STATUS" != "running" ]; then

    echo "ERROR: Container berhenti setelah deployment."

    echo
    echo "Log container:"
    podman logs --tail 100 "$NEW_CONTAINER_NAME" || true

    exit 1
fi

# Pemeriksaan HTTP dilakukan SETELAH composer dan migration,
# karena sebelum itu aplikasi bisa saja belum siap melayani request.
echo "Memeriksa:"
echo "$HEALTH_URL"
echo

HTTP_OK=0
FINAL_HTTP_STATUS=""

for i in {1..30}; do

    FINAL_HTTP_STATUS="$(
        curl \
            --silent \
            --show-error \
            --output /dev/null \
            --write-out '%{http_code}' \
            --max-time 5 \
            "$HEALTH_URL" \
            2>/dev/null || true
    )"

    case "$FINAL_HTTP_STATUS" in

        2??|3??)

            HTTP_OK=1
            break
            ;;

    esac

    sleep 1

done

if [ "$HTTP_OK" -ne 1 ]; then

    echo "ERROR: HTTP health check gagal."
    echo "HTTP status terakhir: ${FINAL_HTTP_STATUS:-Tidak ada response}"

    echo
    echo "Log container:"
    podman logs --tail 100 "$NEW_CONTAINER_NAME" || true

    exit 1
fi

echo "Container : $NEW_CONTAINER_NAME"
echo "Status    : $FINAL_STATUS"
echo "HTTP      : $FINAL_HTTP_STATUS"
echo "Image     : $NEW_IMAGE"
echo

echo "========================================"
echo " Deployment selesai."
echo "========================================"
echo
