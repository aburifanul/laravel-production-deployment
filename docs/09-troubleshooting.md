# 9. Troubleshooting

> Sebelumnya: [8. Google OAuth](08-google-oauth.md) · [Kembali ke README](../README.md)

Cari gejala yang kamu alami. Aturan umum: **perbaiki dari layer terdalam dulu** (container → Laravel → database → origin), baru ke Cloudflare/DNS. Tabel tes berlapisnya ada di [langkah 6.1](06-verifikasi-autostart.md#61-tes-berlapis).

## Daftar gejala

- [HTTP 500](#http-500)
- [`vendor/autoload.php` tidak ditemukan](#vendorautoloadphp-tidak-ditemukan)
- [Error "Class not found" setelah deploy](#error-class-not-found-setelah-deploy)
- [APP_KEY: "No application encryption key"](#app_key-no-application-encryption-key)
- [Database connection refused](#database-connection-refused)
- [Container tidak menerima `.env` baru](#container-tidak-menerima-env-baru)
- [Halaman tanpa CSS/JS](#halaman-tanpa-cssjs)
- [CSS/JS masih memakai `http://`](#cssjs-masih-memakai-http)
- [Port sudah dipakai](#port-sudah-dipakai)
- [`podman compose` tidak jalan](#podman-compose-tidak-jalan)
- [Permission denied di storage](#permission-denied-di-storage)
- [Nilai `${APP_NAME}` tampil apa adanya](#nilai-app_name-tampil-apa-adanya)
- [Google OAuth: error 400 invalid_request](#google-oauth-error-400-invalid_request)
- [deploy.sh tidak menemukan `.env` atau container](#deploysh-tidak-menemukan-env-atau-container)
- [deploy.sh gagal di HTTP health check](#deploysh-gagal-di-http-health-check)
- [Cloudflare: origin berhasil, domain gagal](#cloudflare-origin-berhasil-domain-gagal)
- [Container tidak hidup setelah reboot](#container-tidak-hidup-setelah-reboot)
- [Nginx](#nginx)
- [Apache](#apache)

## HTTP 500

```bash
podman logs --tail 100 <CONTAINER_NAME>
podman exec <CONTAINER_NAME> tail -n 50 storage/logs/laravel.log
podman exec <CONTAINER_NAME> php artisan about
podman exec <CONTAINER_NAME> php artisan optimize:clear
curl -I http://127.0.0.1:<APP_PORT>
```

Jika masih 500, periksa berurutan: `vendor/`, `APP_KEY`, `.env`, koneksi database, permission `storage`, dan PHP extension.

## `vendor/autoload.php` tidak ditemukan

Gejala: `Failed opening required '/app/vendor/autoload.php'`.

Penyebab: folder project di-mount ke `/app`, jadi `vendor/` dari image tertutup dan `vendor/` di folder project belum ada.

```bash
podman exec <CONTAINER_NAME> composer install --no-dev --optimize-autoloader --no-interaction
ls vendor/autoload.php
```

Di lokal (Docker): `docker compose run --rm app composer install`.

## Error "Class not found" setelah deploy

Gejala: `Class "Laravel\Pail\PailServiceProvider" not found` atau class dev package lain.

Penyebab: file cache di `bootstrap/cache/` dibuat saat dependency dev masih terpasang, lalu `vendor/` diganti dengan versi `--no-dev`.

```bash
rm -f bootstrap/cache/*.php
podman exec <CONTAINER_NAME> composer install --no-dev --optimize-autoloader --no-interaction
podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

## APP_KEY: "No application encryption key"

Isi `APP_KEY` **hanya jika memang belum ada**:

```bash
sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|" .env
podman compose up -d --force-recreate
```

`env_file` dibaca saat container dibuat, jadi container harus dibuat ulang. Jangan mengganti `APP_KEY` production yang sudah dipakai: data terenkripsi, session, dan cookie lama jadi tidak terbaca.

Verifikasi (jangan bagikan hasilnya ke publik):

```bash
podman exec <CONTAINER_NAME> php artisan tinker --execute="dump(config('app.key'));"
```

## Database connection refused

Gejala: `SQLSTATE[HY000] [2002] Connection refused`.

```bash
podman exec <CONTAINER_NAME> php artisan migrate:status
systemctl status mariadb
sudo ss -lntp | grep 3306
```

Cek `.env`:

```env
DB_CONNECTION=mysql
DB_HOST=host.containers.internal
DB_PORT=3306
DB_DATABASE=<DB_NAME>
DB_USERNAME=<DB_USER>
DB_PASSWORD=<DB_PASSWORD>
```

Penyebab yang paling sering:

1. **MariaDB hanya listen di `127.0.0.1`.** Ubah `bind-address` menjadi `0.0.0.0` ([lokal](01-persiapan-lokal.md#15-siapkan-database-lokal), [server](03-siapkan-server.md#34-database-di-server)), lalu restart MariaDB.
2. **UFW memblokir koneksi dari container.** Lihat subnet jaringan container dengan `podman network ls` dan `podman network inspect <nama-network>`, lalu izinkan subnet itu saja ke port 3306, misalnya `sudo ufw allow from <SUBNET> to any port 3306`. Jangan membuka 3306 ke semua.
3. **User database salah host atau password salah.** Cek di `sudo mariadb` dengan `SELECT user, host FROM mysql.user;`.

## Container tidak menerima `.env` baru

```bash
podman compose up -d --force-recreate
podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

Jika nilainya masih lama, hapus container lalu buat lagi (atau jalankan `bash scripts/deploy.sh --skip-node`):

```bash
podman stop <CONTAINER_NAME>
podman rm <CONTAINER_NAME>
podman compose up -d
```

## Halaman tanpa CSS/JS

Jika project memakai Vite, asset belum di-build karena `public/build` tidak ada di Git. Build ulang ([langkah 4.5](04-deploy-server.md#45-build-asset-frontend)) atau jalankan `bash scripts/deploy.sh --with-node`, lalu:

```bash
podman exec <CONTAINER_NAME> php artisan optimize:clear
```

## CSS/JS masih memakai `http://`

Pastikan:

```env
APP_ENV=production
APP_URL=https://<APP_DOMAIN>
```

dan `AppServiceProvider` memiliki `URL::forceScheme('https')` ([langkah 1.3](01-persiapan-lokal.md#13-paksa-https-di-production)). Lalu:

```bash
podman compose up -d --force-recreate
podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

## Port sudah dipakai

Gejala: `address already in use` atau `port is already allocated`.

```bash
sudo ss -lntp | grep <APP_PORT>
```

Ganti `APP_PORT` di `.env` dengan port yang kosong (misalnya `8001`), lalu `podman compose up -d --force-recreate`. Ingat untuk mengubah tujuan di Tunnel/Nginx/Apache agar sama dengan port baru.

## `podman compose` tidak jalan

Gejala: `looking for "docker-compose" or "podman-compose"` atau perintah tidak ditemukan.

`podman compose` hanya pembungkus yang butuh provider compose. Pasang:

```bash
sudo apt install -y podman-compose
podman compose version
```

Jika tidak ada di repo distro: `sudo apt install -y pipx && pipx install podman-compose`.

## Permission denied di storage

```bash
sudo chown -R "$USER":"$USER" storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
```

Jika Podman dijalankan sebagai root, pakai `sudo chown -R root:root ...` sesuai user yang menjalankan container.

## Nilai `${APP_NAME}` tampil apa adanya

Gejala: nama pengirim email atau `VITE_APP_NAME` tertulis `${APP_NAME}` secara literal.

Penyebab: variabel di `.env` tidak diekspansi seperti shell saat dibaca lewat `env_file`. Tulis nilai final:

```env
MAIL_FROM_NAME="<PROJECT_NAME>"
VITE_APP_NAME="<PROJECT_NAME>"
```

Lalu `podman compose up -d --force-recreate` dan `optimize:clear`. Aturan yang sama berlaku untuk variabel lain di `.env`.

## Google OAuth: error 400 invalid_request

Periksa `.env`:

```env
GOOGLE_REDIRECT_URI=https://<APP_DOMAIN>/auth/google/callback
```

Cek konfigurasi yang benar-benar terbaca Laravel:

```bash
podman exec <CONTAINER_NAME> php artisan tinker --execute="dump(config('app.url')); dump(config('services.google.redirect'));"
```

Redirect URI di Google Cloud Console harus sama persis. Panduan lengkap: [8. Google OAuth](08-google-oauth.md).

## deploy.sh tidak menemukan `.env` atau container

| Pesan | Penyebab dan perbaikan |
|-------|------------------------|
| `ERROR: File .env tidak ditemukan` | Script harus dijalankan dari project yang punya `.env`. Buat dulu: `cp .env.example .env`, lalu isi nilainya ([langkah 4.2](04-deploy-server.md#42-buat-env-production)) |
| `ERROR: podman/git/curl tidak ditemukan` | Pasang paketnya: `sudo apt install -y podman git curl` |
| `ERROR: Container '...' tidak ditemukan` setelah `up -d` | `CONTAINER_NAME` di `.env` tidak sama dengan nama container yang dibuat Compose. Cek `podman ps -a` dan pastikan `docker-compose.yml` memakai `container_name: ${CONTAINER_NAME:-app}` |
| `ERROR: Container '...' dimiliki project lain` | `CONTAINER_NAME` di `.env` sama dengan container milik folder lain. Script berhenti tanpa menyentuh apa pun. Ganti `CONTAINER_NAME` menjadi nama yang unik, lalu `podman compose up -d` atau jalankan script lagi |
| `WARNING: Pemilik container tidak dapat diverifikasi` | Container itu tidak punya label `com.docker.compose.project.working_dir` (dibuat manual atau oleh provider lain). Script tetap lanjut. Pastikan nama itu memang milik project ini |
| `ERROR: Deployment lain sedang berjalan` | Ada `deploy.sh` lain yang masih berjalan di folder yang sama. Tunggu selesai. Cek dengan `ps aux \| grep deploy.sh`. Kunci otomatis lepas saat script berhenti |
| `ERROR: Argumen tidak dikenal` | Opsi yang tersedia hanya `--with-node` dan `--skip-node` |
| `ERROR: package.json tidak ditemukan` | Kamu memilih build frontend, tetapi project tidak punya `package.json`. Pakai `--skip-node` |

Script membaca `CONTAINER_NAME` dan `APP_PORT` dari `.env`. Jika dua project memakai nama atau port yang sama, container akan bentrok, jadi pastikan keduanya unik per project.

## deploy.sh gagal di HTTP health check

Gejala: `ERROR: HTTP health check gagal.` dengan status `500`, `000`, atau tidak ada response.

Pada tahap ini container baru **sudah menggantikan** yang lama, jadi perbaiki penyebabnya lalu jalankan script lagi. Cek berurutan:

```bash
podman logs --tail 100 <CONTAINER_NAME>
podman exec <CONTAINER_NAME> tail -n 50 storage/logs/laravel.log
curl -I http://127.0.0.1:<APP_PORT>
```

| Status | Kemungkinan penyebab |
|--------|----------------------|
| `500` | Error aplikasi: `APP_KEY` kosong, kredensial database salah, atau `vendor/` tidak lengkap. Lihat [HTTP 500](#http-500) |
| `000` atau kosong | Tidak ada response. Pastikan `APP_PORT` di `.env` sama dengan port yang dipublikasikan container, dan container berstatus `running` |
| `4xx` | Script menganggap status di luar 2xx/3xx sebagai gagal. Jika halaman utama butuh login atau membalas `404`, arahkan health check ke alamat lain: `HEALTH_URL=http://127.0.0.1:<APP_PORT>/up bash scripts/deploy.sh` |

## Cloudflare: origin berhasil, domain gagal

Jika `curl -I http://127.0.0.1:<APP_PORT>` berhasil tetapi `curl -I https://<APP_DOMAIN>` gagal, periksa berurutan:

1. DNS
2. Cloudflare Tunnel
3. Public Hostname
4. Tunnel service
5. Port origin
6. Firewall

```bash
dig <APP_DOMAIN>
systemctl status cloudflared --no-pager
journalctl -u cloudflared -n 100 --no-pager
```

Pastikan route: `<APP_DOMAIN>` → `http://localhost:<APP_PORT>`, dan port itu sama dengan `APP_PORT` di `.env`.

## Container tidak hidup setelah reboot

```bash
systemctl --user status podman-restart.service     # rootless
sudo systemctl status podman-restart.service       # rootful
loginctl show-user "$USER" | grep Linger           # rootless: harus Linger=yes
podman inspect <CONTAINER_NAME> --format '{{.HostConfig.RestartPolicy.Name}}'
```

Policy harus `always`. Perbaikan lengkapnya ada di [langkah 6.2](06-verifikasi-autostart.md#62-autostart-setelah-reboot).

## Nginx

```bash
systemctl status nginx
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
sudo ss -lntp | grep ':80'
```

## Apache

```bash
systemctl status apache2
sudo apache2ctl configtest
sudo apache2ctl -S
sudo tail -f /var/log/apache2/<PROJECT_ALIAS>_error.log
```

---

Belum ketemu? Kumpulkan: nomor langkah yang gagal, output lengkap perintah yang error, dan `podman logs <CONTAINER_NAME>`. Jangan sertakan isi `.env`, `APP_KEY`, atau password.
