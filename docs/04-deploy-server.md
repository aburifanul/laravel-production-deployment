# 4. Deploy di Server

> **Langkah 4 dari 8** · Sebelumnya: [3. Siapkan Server](03-siapkan-server.md) · Berikutnya: [5. Hubungkan Domain](05-hubungkan-domain.md)

Tujuan: aplikasi berjalan di server dan bisa diakses dari `127.0.0.1:<APP_PORT>`. Ini **deploy pertama**; update berikutnya cukup dengan `scripts/deploy.sh` ([langkah 7](07-update-dan-operasional.md)).

Semua perintah dijalankan di server (lewat SSH).

## Isi halaman

- [4.1 Clone project](#41-clone-project)
- [4.2 Buat `.env` production](#42-buat-env-production)
- [4.3 Build dan jalankan container](#43-build-dan-jalankan-container)
- [4.4 Install dependency PHP](#44-install-dependency-php)
- [4.5 Build asset frontend](#45-build-asset-frontend)
- [4.6 Setup Laravel](#46-setup-laravel)
- [4.7 Cek origin](#47-cek-origin)

## 4.1 Clone project

```bash
sudo mkdir -p /var/www
sudo chown "$USER":"$USER" /var/www
cd /var/www
git clone <REPOSITORY_URL> <APP_DOMAIN>
cd /var/www/<APP_DOMAIN>
```

Nama folder memakai `<APP_DOMAIN>` (misalnya `akademik.example.com`) supaya mudah dikenali kalau satu server punya banyak project.

Jika repo **public**, `<REPOSITORY_URL>` cukup `https://github.com/<GITHUB_USER>/<REPO_NAME>.git`.

<details>
<summary><b>Repo private: pakai Deploy Key</b></summary>

Buat key khusus project di server:

```bash
ssh-keygen -t ed25519 -C "deploy-<PROJECT_ALIAS>" -f ~/.ssh/deploy_<PROJECT_ALIAS> -N ""
cat ~/.ssh/deploy_<PROJECT_ALIAS>.pub
```

Di GitHub: repo → **Settings** → **Deploy keys** → **Add deploy key** → tempel isi file `.pub` (biarkan read-only).

Tambahkan ke `~/.ssh/config`:

```text
Host github-<PROJECT_ALIAS>
    HostName github.com
    User git
    IdentityFile ~/.ssh/deploy_<PROJECT_ALIAS>
    IdentitiesOnly yes
```

```bash
chmod 600 ~/.ssh/config
git clone git@github-<PROJECT_ALIAS>:<GITHUB_USER>/<REPO_NAME>.git <APP_DOMAIN>
```

</details>

## 4.2 Buat `.env` production

```bash
cp .env.example .env
```

Isi `APP_KEY` (cukup **sekali** di awal):

```bash
sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|" .env
```

Edit nilai lainnya:

```bash
nano .env
```

Nilai yang **wajib** diisi:

```env
APP_NAME="<PROJECT_NAME>"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://<APP_DOMAIN>

APP_PORT=8000
CONTAINER_NAME=<CONTAINER_NAME>

DB_HOST=host.containers.internal
DB_DATABASE=<DB_NAME>
DB_USERNAME=<DB_USER>
DB_PASSWORD=<DB_PASSWORD>
```

Pastikan tidak ada placeholder yang tertinggal:

```bash
grep -n '<' .env || echo "OK: tidak ada placeholder tersisa"
```

> **Penting:** satu server banyak project? Beri tiap project `APP_PORT` dan `CONTAINER_NAME` yang berbeda (misalnya 8000, 8001, 8002), kalau tidak container akan bentrok.

Jika memakai Google Login, lanjutkan ke [Google OAuth](08-google-oauth.md) setelah aplikasi berjalan.

## 4.3 Build dan jalankan container

```bash
podman compose build --no-cache
podman compose up -d
podman ps
```

Contoh output:

```text
CONTAINER ID  IMAGE                           STATUS
xxxxxxxxxxxx  localhost/<PROJECT>_app:latest   Up
```

Container sudah `Up`, tetapi aplikasi belum bisa dibuka karena `vendor/` belum ada. Itu dibuat di langkah berikutnya.

## 4.4 Install dependency PHP

Folder project di-mount ke `/app`, jadi `vendor/` harus ada di folder project. Buat lewat container (tidak perlu PHP di host server):

```bash
podman exec <CONTAINER_NAME> composer install --no-dev --optimize-autoloader --no-interaction
```

Cek hasilnya:

```bash
ls vendor/autoload.php
```

## 4.5 Build asset frontend

Lewati jika project tidak punya `package.json`.

```bash
podman run --rm \
    -v "$PWD:/app:Z" \
    -w /app \
    docker.io/library/node:24-alpine \
    sh -c "npm ci && npm run build"
```

Hasilnya masuk ke `public/build/`.

## 4.6 Setup Laravel

```bash
podman exec <CONTAINER_NAME> php artisan about
podman exec <CONTAINER_NAME> php artisan migrate --force
podman exec <CONTAINER_NAME> php artisan storage:link
podman exec <CONTAINER_NAME> php artisan optimize
```

`--force` diperlukan karena di production Laravel meminta konfirmasi sebelum migrate.

> **Bahaya:** jangan pernah menjalankan `php artisan migrate:fresh` di production. Perintah itu menjalankan `DROP TABLE` sehingga **seluruh data hilang**. Untuk deployment normal selalu `migrate --force`.

Cek storage link:

```bash
podman exec <CONTAINER_NAME> ls -la public
```

Harus ada baris `storage -> /app/storage/app/public`.

## 4.7 Cek origin

```bash
curl -I http://127.0.0.1:<APP_PORT>
```

Yang diharapkan:

```text
HTTP/1.1 200 OK
Server: FrankenPHP Caddy
```

> **Tip:** jika origin belum `200`, **jangan lanjut** ke domain atau Cloudflare. Perbaiki dulu di sini, karena masalah di domain hampir selalu berasal dari origin. Lihat [Troubleshooting](09-troubleshooting.md).

---

**Selanjutnya:** [5. Hubungkan Domain →](05-hubungkan-domain.md)
