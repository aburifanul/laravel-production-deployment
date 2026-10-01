# 1. Persiapan Lokal

> **Langkah 1 dari 8** · Berikutnya: [2. Push ke GitHub](02-push-github.md) · [Kembali ke README](../README.md)

Tujuan: project Laravel sudah berjalan di container (FrankenPHP + Caddy) di laptop **sebelum** menyentuh server. Kalau di lokal sudah normal, deploy ke server tinggal mengulang pola yang sama.

Di panduan ini `<PLACEHOLDER>` harus diganti dengan nilai project kamu. Daftar lengkapnya ada di [README](../README.md#placeholder).

## Isi halaman

- [1.1 Persyaratan](#11-persyaratan)
- [1.2 Tambahkan file container](#12-tambahkan-file-container)
- [1.3 Paksa HTTPS di production](#13-paksa-https-di-production)
- [1.4 Siapkan `.env.example`](#14-siapkan-envexample)
- [1.5 Siapkan database lokal](#15-siapkan-database-lokal)
- [1.6 Buat `.env` lokal](#16-buat-env-lokal)
- [1.7 Pastikan folder `vendor` ada](#17-pastikan-folder-vendor-ada)
- [1.8 Build asset frontend](#18-build-asset-frontend)
- [1.9 Build dan jalankan](#19-build-dan-jalankan)
- [1.10 Cek hasilnya](#110-cek-hasilnya)

## 1.1 Persyaratan

| Kebutuhan | Keterangan |
|-----------|------------|
| Git | untuk push ke GitHub |
| Docker + Docker Compose v2 | menjalankan container di lokal |
| MariaDB / MySQL | database ada di **host** (laptop), bukan di container |
| Project Laravel | sudah bisa dijalankan |

```bash
git --version
docker --version
docker compose version
```

## 1.2 Tambahkan file container

Dari root project Laravel:

```bash
mkdir -p docker/php scripts
```

Struktur yang ditambahkan:

```text
<PROJECT>/
├── docker/
│   └── php/
│       ├── Dockerfile
│       ├── Caddyfile
│       └── php.ini
├── scripts/
│   └── deploy.sh        (dipakai di server, lihat langkah 7)
├── docker-compose.yml
├── .dockerignore
└── .env.example
```

### `docker/php/Dockerfile`

```dockerfile
FROM docker.io/dunglas/frankenphp:php8.4-alpine

RUN install-php-extensions \
    pdo_mysql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    intl \
    opcache \
    redis

COPY --from=docker.io/library/composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY . .

ENV COMPOSER_ALLOW_SUPERUSER=1

RUN rm -f \
    bootstrap/cache/*.php

RUN composer install \
    --optimize-autoloader \
    --no-dev \
    --no-interaction

RUN mkdir -p \
    storage/logs \
    storage/framework/cache \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache \
    && chown -R www-data:www-data /app \
    && chmod -R 775 storage bootstrap/cache

COPY docker/php/Caddyfile /etc/caddy/Caddyfile

COPY docker/php/php.ini \
    /usr/local/etc/php/conf.d/99-custom.ini

EXPOSE 80 443 443/udp

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
```

Yang dilakukan file ini:

- Memakai image **FrankenPHP** (PHP 8.4 + Caddy dalam satu binary) versi Alpine.
- `install-php-extensions` memasang extension PHP yang umum dipakai Laravel. Butuh extension lain? Tambahkan di baris itu.
- `composer install --no-dev` memasang dependency production ke dalam image.
- `rm -f bootstrap/cache/*.php` membuang cache bootstrap dari mesin development (misalnya `packages.php` yang menyebut paket dev) supaya tidak bentrok dengan `--no-dev`.
- Image memakai nama lengkap `docker.io/...` sehingga Podman tidak kena masalah *short-name image resolution*.

### `docker/php/Caddyfile`

```caddyfile
{
    frankenphp
    auto_https off
    order php_server before file_server
}

:80 {
    root * /app/public

    encode zstd gzip

    @hiddenFiles {
        path */.*
    }

    error @hiddenFiles 404

    php_server
}
```

Caddy melayani folder `public` Laravel lewat FrankenPHP. `auto_https off` karena HTTPS ditangani layer di depan container (Cloudflare, Nginx, atau Apache), bukan oleh container.

### `docker/php/php.ini`

```ini
[PHP]

max_execution_time = 300
max_input_time = 300
memory_limit = 256M

upload_max_filesize = 64M
max_file_uploads = 20
post_max_size = 100M

[opcache]

opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 4000
opcache.revalidate_freq = 2
```

Batas upload 64 MB dan `post_max_size` 100 MB. Sesuaikan dengan kebutuhan aplikasi.

### `docker-compose.yml`

```yaml
services:
  app:
    build:
      context: .
      dockerfile: docker/php/Dockerfile

    container_name: ${CONTAINER_NAME:-app}

    restart: always

    extra_hosts:
      - "host.containers.internal:host-gateway"

    ports:
      - "127.0.0.1:${APP_PORT:-8000}:80"

    env_file:
      - .env

    volumes:
      - ./:/app
      - ./docker/php/Caddyfile:/etc/caddy/Caddyfile
      - ./docker/php/php.ini:/usr/local/etc/php/conf.d/99-custom.ini
      - caddy_data:/data
      - caddy_config:/config

    networks:
      - app_network

networks:
  app_network:
    driver: bridge

volumes:
  caddy_data:
    driver: local

  caddy_config:
    driver: local
```

Penjelasan bagian pentingnya:

| Bagian | Fungsi |
|--------|--------|
| `container_name: ${CONTAINER_NAME:-app}` | Nama container dibaca dari `.env`, jadi satu server bisa menjalankan banyak project tanpa bentrok |
| `restart: always` | Container hidup lagi setelah crash atau reboot (di Podman perlu langkah tambahan, lihat [langkah 6](06-verifikasi-autostart.md)) |
| `extra_hosts: host.containers.internal` | Nama host ke mesin induk. **Sama untuk Docker dan Podman**, jadi `DB_HOST` di `.env` tidak perlu diubah antara lokal dan server |
| `127.0.0.1:${APP_PORT:-8000}:80` | Port hanya terbuka di localhost, **tidak** ke internet. Akses publik lewat Cloudflare Tunnel, Nginx, atau Apache |
| `./:/app` | Folder project di-mount ke container. Konsekuensinya container memakai file dari folder project, **termasuk `vendor/`** (lihat [1.7](#17-pastikan-folder-vendor-ada)) |
| `caddy_data`, `caddy_config` | Volume data internal Caddy |

### `.dockerignore`

```text
.git
.github

.env
.env.*

!.env.example

node_modules
vendor

bootstrap/cache/*.php

storage/logs/*
storage/framework/cache/*
storage/framework/sessions/*
storage/framework/views/*
```

File yang tidak ikut dikirim saat `build` (secret `.env`, `vendor`, cache, log). `.env.example` sengaja dikecualikan dari aturan `.env.*` lewat `!.env.example`.

### `scripts/deploy.sh`

Script ini dipakai di server. Isi lengkapnya dibahas di [langkah 7](07-update-dan-operasional.md#71-deploysh). Untuk sekarang cukup buat filenya dan beri izin eksekusi:

```bash
chmod +x scripts/deploy.sh
```

## 1.3 Paksa HTTPS di production

Di belakang Cloudflare atau reverse proxy, Laravel perlu tahu bahwa request publik memakai HTTPS. Edit `app/Providers/AppServiceProvider.php`:

```php
<?php

namespace App\Providers;

use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        if (config('app.env') === 'production') {
            URL::forceScheme('https');
        }
    }
}
```

Jika `AppServiceProvider` kamu sudah berisi kode lain, cukup tambahkan `use Illuminate\Support\Facades\URL;` dan blok `if` di dalam `boot()`. Di lokal (`APP_ENV=local`) kode ini tidak aktif.

## 1.4 Siapkan `.env.example`

Ganti isi `.env.example` project dengan template berikut. File ini dipakai **di lokal maupun di server**; nilai `<...>` diisi saat membuat `.env`.

```env
APP_NAME=<PROJECT_NAME> # Contoh: "Akademik Student"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://<APP_DOMAIN>

# Dibaca docker-compose.yml
# Gunakan port host (lokal) yang belum digunakan aplikasi lain.
# Jika port 8000 masih digunakan, gunakan port lain atau matikan aplikasi yang menggunakannya.
APP_PORT=8000
CONTAINER_NAME=<CONTAINER_NAME> # Gunakan "-" dan tanpa spasi. Contoh: Akademik-Student

APP_LOCALE=en
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US

APP_MAINTENANCE_DRIVER=file
# APP_MAINTENANCE_STORE=database

# PHP_CLI_SERVER_WORKERS=4

BCRYPT_ROUNDS=12

LOG_CHANNEL=stack
LOG_STACK=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=error

DB_CONNECTION=mysql
DB_HOST=host.containers.internal
DB_PORT=3306
DB_DATABASE=<DB_NAME>
DB_USERNAME=<DB_USER>
DB_PASSWORD=<DB_PASSWORD>

SESSION_DRIVER=database
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=null

BROADCAST_CONNECTION=log
FILESYSTEM_DISK=local
QUEUE_CONNECTION=database

CACHE_STORE=database
# CACHE_PREFIX=

MEMCACHED_HOST=127.0.0.1

REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=log
MAIL_SCHEME=null
MAIL_HOST=127.0.0.1
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

# Google OAuth / Laravel Socialite
# Isi jika aplikasi menggunakan login Google
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=https://<APP_DOMAIN>/auth/google/callback

VITE_APP_NAME="${APP_NAME}"
```

Hal yang perlu diperhatikan:

- Isinya `.env.example` bawaan Laravel yang disesuaikan, jadi key bawaan (Mail, Redis, AWS, Vite) tetap ada.
- **Yang berbeda dari bawaan Laravel:** `APP_ENV=production`, `APP_DEBUG=false`, `LOG_LEVEL=error`, database `mysql` yang mengarah ke host, serta key tambahan `APP_PORT`, `CONTAINER_NAME`, dan `GOOGLE_*`.
- Komentar setelah nilai (`# Contoh: ...`) hanya petunjuk. Jika nama project memakai spasi, **beri tanda kutip**: `APP_NAME="Akademik Student"`.
- `CONTAINER_NAME` memakai `-` tanpa spasi, misalnya `akademik-student`.
- Jika project punya key tambahan sendiri, biarkan tetap ada.

## 1.5 Siapkan database lokal

Masuk ke MariaDB:

```bash
sudo mariadb
```

```sql
CREATE DATABASE <DB_NAME>;

CREATE USER '<DB_USER>'@'%' IDENTIFIED BY '<DB_PASSWORD>';

GRANT ALL PRIVILEGES ON <DB_NAME>.* TO '<DB_USER>'@'%';

FLUSH PRIVILEGES;
```

Container harus bisa menjangkau MariaDB di host. Cek dulu:

```bash
sudo ss -lntp | grep 3306
```

Jika hanya muncul `127.0.0.1:3306`, container **tidak** bisa terhubung. Ubah `bind-address` di konfigurasi MariaDB (biasanya `/etc/mysql/mariadb.conf.d/50-server.cnf`):

```ini
bind-address = 0.0.0.0
```

```bash
sudo systemctl restart mariadb
sudo ss -lntp | grep 3306
```

> **Peringatan:** `0.0.0.0` membuat MariaDB menerima koneksi dari semua interface. Pakai hanya di jaringan tepercaya dan jangan buka port `3306` ke internet.

## 1.6 Buat `.env` lokal

```bash
cp .env.example .env
```

Isi `APP_KEY` (cukup **sekali** di awal):

```bash
sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|" .env
```

Lalu edit `.env`:

```bash
nano .env
```

Nilai yang diubah untuk **lokal**:

```env
APP_NAME="<PROJECT_NAME>"
APP_ENV=local
APP_DEBUG=true
APP_URL=http://127.0.0.1:8000

APP_PORT=8000
CONTAINER_NAME=<PROJECT_ALIAS>-app

LOG_LEVEL=debug

DB_HOST=host.containers.internal
DB_DATABASE=<DB_NAME>
DB_USERNAME=<DB_USER>
DB_PASSWORD=<DB_PASSWORD>
```

Jika port `8000` sudah dipakai aplikasi lain di laptop, ganti `APP_PORT` (misalnya `8001`) dan sesuaikan `APP_URL`.

> **Peringatan:** jangan jalankan perintah `sed ... APP_KEY` atau `php artisan key:generate --force` pada aplikasi yang sudah berjalan di production. `APP_KEY` dipakai untuk enkripsi. Mengganti nilainya membuat data terenkripsi, session, dan cookie lama tidak bisa dipakai.

## 1.7 Pastikan folder `vendor` ada

Karena folder project di-mount ke `/app`, container memakai `vendor/` dari folder project, **bukan** dari image. Cek:

```bash
ls vendor/autoload.php
```

Jika belum ada (misalnya project baru di-clone), buat lewat container supaya tidak perlu PHP di host:

```bash
docker compose build
docker compose run --rm app composer install
```

Di lokal dependency dev ikut terpasang, itu normal.

## 1.8 Build asset frontend

Lewati langkah ini jika project tidak punya `package.json`.

Folder `public/build` tidak ikut di Git, jadi asset Vite/Tailwind harus di-build:

```bash
docker run --rm -v "$PWD":/app -w /app node:24-alpine sh -c "npm ci && npm run build"
```

Jika Node.js sudah terpasang di laptop, cukup `npm ci && npm run build`.

## 1.9 Build dan jalankan

```bash
docker compose build --no-cache
docker compose up -d
docker compose ps
```

Contoh output:

```text
NAME                STATUS
<PROJECT_ALIAS>-app Up
```

Setup Laravel:

```bash
docker compose exec app php artisan migrate
docker compose exec app php artisan storage:link
docker compose exec app php artisan about
```

> **Tip:** `env_file` hanya dibaca saat container dibuat. Setelah mengubah `.env`, jalankan `docker compose up -d --force-recreate`.

## 1.10 Cek hasilnya

```bash
curl -I http://127.0.0.1:8000
```

Yang diharapkan:

```text
HTTP/1.1 200 OK
Server: FrankenPHP Caddy
```

Buka `http://127.0.0.1:8000` di browser dan coba fitur utama. Jika sudah normal, rantai ini sudah bekerja:

```text
Laravel → FrankenPHP → Caddy → Container → MariaDB (host)
```

Ada masalah? Lihat [Troubleshooting](09-troubleshooting.md).

---

**Selanjutnya:** [2. Push ke GitHub →](02-push-github.md)
