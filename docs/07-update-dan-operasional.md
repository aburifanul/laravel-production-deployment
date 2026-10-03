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

Script ini mengotomatiskan seluruh langkah update di server, lengkap dengan pengecekan di awal, penggantian container, dan health check di akhir. Simpan di `scripts/deploy.sh` dan beri izin eksekusi (`chmod +x scripts/deploy.sh`).

```bash
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
```

**Tahapan yang dijalankan**

| Tahap | Yang dilakukan |
|-------|----------------|
| Pre-flight | Memastikan `podman`, `git`, `curl`, `docker-compose.yml`, dan `.env` ada. Mengunci folder supaya tidak ada dua deployment berjalan bersamaan. Membaca `CONTAINER_NAME` dan `APP_PORT` dari `.env` |
| Current Container | Mencari container lama berdasarkan `CONTAINER_NAME`, **memastikan container itu milik folder ini**, lalu menampilkan nama, status, dan image-nya |
| Git | `git pull origin main` mengambil kode terbaru |
| Frontend | Membangun asset dengan `npm ci && npm run build` di container Node sementara, atau melewatinya (lihat [7.2](#72-alur-update)) |
| Build Image | `podman compose build`. Container lama **masih berjalan** dan melayani pengunjung selama build |
| Replace Container | `podman stop` lalu `podman rm` container lama, kemudian `podman compose up -d` |
| Wait for Container | Menunggu container baru berstatus `running` (maksimal 30 detik). Jika berhenti, log ditampilkan |
| Composer | `composer install --no-dev --optimize-autoloader` supaya `vendor/` sesuai `composer.lock` |
| Laravel | `migrate --force`, `optimize:clear`, lalu `optimize` |
| Final Deployment Check | Memastikan container masih `running` dan `HEALTH_URL` membalas status 2xx atau 3xx (dicoba berulang sampai 30 detik) |

**Pengaman bawaan**

- **Container dicari lewat `CONTAINER_NAME` di `.env`, bukan lewat label Compose.** Semua project memakai service bernama `app`, jadi label itu tidak cukup untuk membedakan project.
- **Kepemilikan diverifikasi.** Container yang ditemukan harus punya label `com.docker.compose.project.working_dir` yang sama dengan folder ini. Jika nama itu dipakai project lain, script berhenti dengan `ERROR: Container '...' dimiliki project lain` **sebelum menyentuh apa pun** (belum ada `git pull`, `stop`, atau `rm`). Jika label tidak ada (container dibuat manual), script hanya memberi peringatan dan lanjut.
- **Satu deployment per folder.** Menjalankan script kedua kali di folder yang sama saat yang pertama belum selesai langsung ditolak. Folder project lain tidak terpengaruh.
- **Berhenti di error pertama** (`set -Eeuo pipefail`), jadi tidak ada langkah yang jalan di atas kondisi yang rusak.
- **Health check dilakukan setelah composer dan migration**, karena sebelum itu aplikasi bisa saja belum siap melayani request (misalnya `vendor/` belum lengkap atau tabel baru belum dibuat).

**Pengaturan**

| Hal | Cara mengatur |
|-----|---------------|
| Nama container dan port | `CONTAINER_NAME` dan `APP_PORT` di `.env`. Komentar inline (`# ...`) dan tanda kutip diabaikan |
| Alamat health check | Secara bawaan `http://127.0.0.1:<APP_PORT>/`. Ubah dengan `HEALTH_URL=http://127.0.0.1:<APP_PORT>/up bash scripts/deploy.sh`. Laravel 11 ke atas punya route `/up`. Gunakan alamat publik yang membalas 2xx/3xx jika halaman utama butuh login atau membalas 404 |
| Branch | Script memakai `main`. Jika branch production berbeda, ubah baris `git pull origin main` |

**Banyak project dalam satu server**

Script aman dipakai di banyak project selama setiap project punya identitas sendiri:

| Harus unik per project | Contoh project A | Contoh project B |
|------------------------|------------------|------------------|
| Folder | `/var/www/a.example.com` | `/var/www/b.example.com` |
| `CONTAINER_NAME` | `a-app` | `b-app` |
| `APP_PORT` | `8000` | `8001` |

Network dan volume Compose sudah otomatis memakai awalan nama folder, jadi tidak bentrok. Cek apa saja yang terpakai sebelum menambah project baru:

```bash
podman ps -a --format "table {{.Names}}\t{{.Ports}}"
```

Jalankan script dari folder masing-masing: `cd /var/www/<APP_DOMAIN> && bash scripts/deploy.sh`.

**Batasan yang perlu diketahui**

- **Tidak ada rollback otomatis.** Lihat tabel di bawah.
- **Ada downtime singkat**, dari container lama dihentikan sampai container baru siap (beberapa detik hingga puluhan detik). Ini bukan zero-downtime deployment.
- **Butuh provider compose.** Script memakai `podman compose`, yang meneruskan ke `podman-compose` atau `docker-compose`. Script ini diuji di Armbian dengan Podman 4.9.3 dan podman-compose 1.0.6. Versi lain belum diuji.
- **Label `working_dir` bergantung pada compose provider.** Provider yang tidak memasang label itu membuat verifikasi kepemilikan hanya berupa peringatan.

**Jika deployment gagal**

Script menampilkan ringkasan `Deployment gagal`:

| Gagal di tahap | Kondisi production |
|----------------|--------------------|
| Sebelum "Replace Container" (git pull, build frontend, build image) | Container lama **belum disentuh** dan tetap melayani pengunjung |
| Setelah container diganti (start, composer, migrate, health check) | Container lama sudah dihapus. Log container baru ditampilkan. **Tidak ada rollback otomatis**: perbaiki penyebabnya lalu jalankan script lagi |

Image sebelumnya tetap tersimpan di server (nama image lama ditampilkan di ringkasan), jadi pemulihan manual tetap memungkinkan. Panduan gejala umum ada di [Troubleshooting](09-troubleshooting.md#deploysh-gagal-di-http-health-check).

## 7.2 Alur update

Setelah kode diubah di lokal dan di-push ke GitHub:

```bash
cd /var/www/<APP_DOMAIN>
bash scripts/deploy.sh
```

Script menanyakan apakah project memakai Node.js / Vite. Untuk melewati pertanyaan itu, gunakan opsi:

| Perintah | Fungsi |
|----------|--------|
| `bash scripts/deploy.sh` | Menanyakan `Pilih [1/2]`. Pilih **1** jika project punya `package.json` (Vite/Tailwind), **2** jika tidak |
| `bash scripts/deploy.sh --with-node` | Langsung build frontend tanpa bertanya |
| `bash scripts/deploy.sh --skip-node` | Langsung lewati build frontend tanpa bertanya |

Karena opsi ini, update bisa dijalankan tanpa interaksi, misalnya dari laptop lewat SSH:

```bash
ssh <SERVER_USER>@<SERVER_IP> 'cd /var/www/<APP_DOMAIN> && bash scripts/deploy.sh --skip-node'
```

Contoh ringkasan di akhir deployment yang berhasil:

```text
========================================
 Final Deployment Check
========================================

Memeriksa:
http://127.0.0.1:8000/

Container : akademik-app
Status    : running
HTTP      : 200
Image     : localhost/<PROJECT>_app:latest

========================================
 Deployment selesai.
========================================
```

Setelah itu cek dari luar:

```bash
curl -I https://<APP_DOMAIN>
```

> **Catatan downtime:** build image (tahap paling lama) berjalan saat container lama masih melayani pengunjung. Aplikasi hanya tidak melayani request dari saat container lama dihentikan sampai container baru siap, biasanya beberapa detik hingga puluhan detik.

## 7.3 Update manual (tanpa script)

Urutan yang sama dengan script:

```bash
cd /var/www/<APP_DOMAIN>

git pull origin main

podman compose build

podman stop <CONTAINER_NAME>
podman rm <CONTAINER_NAME>
podman compose up -d

podman exec <CONTAINER_NAME> composer install --no-dev --optimize-autoloader --no-interaction
podman exec <CONTAINER_NAME> php artisan migrate --force
podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize

curl -I http://127.0.0.1:<APP_PORT>
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

`env_file` hanya dibaca **saat container dibuat**. Jika hanya `.env` yang berubah, container harus dibuat ulang. Cara termudah:

```bash
cd /var/www/<APP_DOMAIN>
bash scripts/deploy.sh --skip-node
```

Atau manual:

```bash
cd /var/www/<APP_DOMAIN>

podman compose up -d --force-recreate

podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

Jika `--force-recreate` tidak membuat ulang container di versi `podman-compose` kamu, hapus container secara manual lalu buat lagi:

```bash
podman stop <CONTAINER_NAME>
podman rm <CONTAINER_NAME>
podman compose up -d
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
