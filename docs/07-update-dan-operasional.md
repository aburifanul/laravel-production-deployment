# 7. Update dan Operasional

> **Langkah 7 dari 8** · Sebelumnya: [6. Verifikasi dan Autostart](06-verifikasi-autostart.md) · Berikutnya: [8. Google OAuth](08-google-oauth.md) (opsional)

Setelah aplikasi online, pekerjaan sehari-hari adalah **update kode** dan **merawat server**. Halaman ini membahas keduanya.

## Isi halaman

- [7.1 `deploy.sh`](#71-deploysh)
- [7.2 Alur update](#72-alur-update)
- [7.3 Update manual (tanpa script)](#73-update-manual-tanpa-script)
- [7.4 Mengubah `.env`](#74-mengubah-env)
- [7.5 Perintah Podman yang sering dipakai](#75-perintah-podman-yang-sering-dipakai)
- [7.6 Log](#76-log)
- [7.7 Restart dan stop](#77-restart-dan-stop)
- [7.8 Maintenance mode](#78-maintenance-mode)
- [7.9 Backup dan restore database](#79-backup-dan-restore-database)
- [7.10 Membersihkan image](#710-membersihkan-image)

## 7.1 `deploy.sh`

Script ini mengotomatiskan seluruh langkah update di server. Simpan di `scripts/deploy.sh` dan beri izin eksekusi (`chmod +x scripts/deploy.sh`).

```bash
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

OLD_CONTAINER="$(
    podman ps -aq \
        --filter "label=com.docker.compose.service=app" \
        | head -n 1
)"

if [ -n "$OLD_CONTAINER" ]; then

    OLD_CONTAINER_NAME="$(
        podman inspect "$OLD_CONTAINER" \
            --format '{{.Name}}' \
            | sed 's#^/##'
    )"

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

CONTAINER_NAME="$(
    podman ps \
        --filter "label=com.docker.compose.service=app" \
        --format "{{.Names}}" \
        | head -n 1
)"

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

    STATUS="$(
        podman inspect "$CONTAINER_NAME" \
            --format '{{.State.Status}}' \
            2>/dev/null || true
    )

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

STATUS="$(
    podman inspect "$CONTAINER_NAME" \
        --format '{{.State.Status}}'
)"

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

FINAL_STATUS="$(
    podman inspect "$CONTAINER_NAME" \
        --format '{{.State.Status}}'
)"

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
```

Tahapan yang dijalankan:

| Tahap | Yang dilakukan |
|-------|----------------|
| Git | `git pull origin main` mengambil kode terbaru |
| Frontend | Menanyakan apakah project memakai Node/Vite. Jika **1**, menjalankan `npm ci && npm run build` di container Node sementara. Jika **2**, dilewati |
| Container | `podman compose build` lalu `up -d` |
| Cari container | Mengambil ID container service `app` lewat `podman compose ps -q app`, lalu menunggu 5 detik |
| Composer | `composer install --no-dev --optimize-autoloader` supaya `vendor/` selalu sesuai `composer.lock` |
| Laravel | `migrate --force`, `optimize:clear`, lalu `optimize` |

Script berhenti di error pertama (`set -euo pipefail`), jadi tidak ada langkah yang jalan di atas kondisi yang rusak.

## 7.2 Alur update

Setelah kode diubah di lokal dan di-push ke GitHub:

```bash
cd /var/www/<APP_DOMAIN>
bash scripts/deploy.sh
```

Saat ditanya `Pilih [1/2]`:

- Pilih **1** jika project punya `package.json` (memakai Vite/Tailwind).
- Pilih **2** jika tidak.

Setelah selesai, cek:

```bash
curl -I https://<APP_DOMAIN>
```

> **Catatan:** script ini interaktif (menunggu input), jadi jalankan dari terminal, bukan dari cron.

## 7.3 Update manual (tanpa script)

Urutan yang sama dengan script:

```bash
cd /var/www/<APP_DOMAIN>

git pull origin main

podman compose build
podman compose up -d

podman exec <CONTAINER_NAME> composer install --no-dev --optimize-autoloader --no-interaction
podman exec <CONTAINER_NAME> php artisan migrate --force
podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

Jika project memakai Vite, build asset sebelum `podman compose build`:

```bash
podman run --rm \
    -v "$PWD:/app:Z" \
    -w /app \
    docker.io/library/node:24-alpine \
    sh -c "npm ci && npm run build"
```

## 7.4 Mengubah `.env`

`env_file` hanya dibaca **saat container dibuat**. Jika hanya `.env` yang berubah, container harus dibuat ulang:

```bash
cd /var/www/<APP_DOMAIN>

podman compose up -d --force-recreate

podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

## 7.5 Perintah Podman yang sering dipakai

| Tujuan | Perintah |
|--------|----------|
| Container aktif | `podman ps` |
| Semua container | `podman ps -a` |
| Daftar image | `podman images` |
| Detail container | `podman inspect <CONTAINER_NAME>` |
| Masuk container | `podman exec -it <CONTAINER_NAME> sh` |
| Jalankan artisan | `podman exec <CONTAINER_NAME> php artisan about` |
| Pemakaian resource | `podman stats <CONTAINER_NAME>` |

## 7.6 Log

```bash
# Log FrankenPHP / Caddy
podman logs <CONTAINER_NAME>
podman logs -f <CONTAINER_NAME>
podman logs --tail 100 <CONTAINER_NAME>

# Log Laravel
podman exec <CONTAINER_NAME> tail -f storage/logs/laravel.log
podman exec <CONTAINER_NAME> ls -lah storage/logs
```

Karena folder project di-mount, log Laravel juga bisa dibaca langsung di host: `/var/www/<APP_DOMAIN>/storage/logs/laravel.log`.

## 7.7 Restart dan stop

```bash
podman restart <CONTAINER_NAME>

podman compose restart

podman compose down
```

> **Peringatan:** `podman compose down` berbeda dengan `podman compose down -v`. Jangan memakai `-v` sembarangan karena dapat **menghapus volume**.

## 7.8 Maintenance mode

```bash
podman exec <CONTAINER_NAME> php artisan down    # aktifkan
podman exec <CONTAINER_NAME> php artisan up      # nonaktifkan
```

## 7.9 Backup dan restore database

Backup:

```bash
mysqldump -u <DB_USER> -p <DB_NAME> > <DB_NAME>-backup.sql
```

Jika MariaDB membutuhkan host tertentu:

```bash
mysqldump -h 127.0.0.1 -u <DB_USER> -p <DB_NAME> > <DB_NAME>-backup.sql
```

Restore:

```bash
mysql -u <DB_USER> -p <DB_NAME> < <DB_NAME>-backup.sql
```

> **Tip:** simpan backup di lokasi yang aman dan **terpisah dari server production**. Backup yang hanya ada di server yang sama ikut hilang saat server bermasalah.

## 7.10 Membersihkan image

Cek dulu sebelum menghapus:

```bash
podman images
podman image prune
```

> **Peringatan:** jangan memakai cleanup agresif di production tanpa memeriksa image dan volume yang sedang dipakai.

---

**Selanjutnya:** [8. Google OAuth →](08-google-oauth.md) (opsional) atau [9. Troubleshooting →](09-troubleshooting.md)
