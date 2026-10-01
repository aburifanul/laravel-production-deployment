# 6. Verifikasi dan Autostart

> **Langkah 6 dari 8** · Sebelumnya: [5. Hubungkan Domain](05-hubungkan-domain.md) · Berikutnya: [7. Update dan Operasional](07-update-dan-operasional.md)

Tujuan: memastikan semua layer benar, dan aplikasi **tetap online setelah server restart**.

## Isi halaman

- [6.1 Tes berlapis](#61-tes-berlapis)
- [6.2 Autostart setelah reboot](#62-autostart-setelah-reboot)
- [6.3 Tes reboot](#63-tes-reboot)
- [6.4 Checklist akhir](#64-checklist-akhir)

## 6.1 Tes berlapis

Periksa dari layer terdalam ke terluar. Berhenti di layer pertama yang gagal dan perbaiki di situ.

| Layer | Target | Perintah | Expected |
|:-----:|--------|----------|----------|
| 1 | Container | `podman ps` | Status `Up` |
| 2 | Laravel | `podman exec <CONTAINER_NAME> php artisan about` | Info aplikasi tampil |
| 3 | Database | `podman exec <CONTAINER_NAME> php artisan migrate:status` | Daftar migration tampil |
| 4 | Port | `sudo ss -lntp \| grep <APP_PORT>` | Listen di `127.0.0.1` |
| 5 | Origin | `curl -I http://127.0.0.1:<APP_PORT>` | `200 OK` |
| 6 | Reverse proxy | `curl -I -H "Host: <APP_DOMAIN>" http://127.0.0.1` | `200 OK` (hanya Nginx/Apache) |
| 7 | Publik | `curl -I https://<APP_DOMAIN>` | `HTTP/2 200` |

Jika semua layer lolos, seluruh jalur sudah benar:

```text
Domain → Cloudflare → Tunnel/Proxy → Podman → FrankenPHP → Laravel → MariaDB
```

## 6.2 Autostart setelah reboot

`docker-compose.yml` memakai `restart: always`. Di Podman, container baru dihidupkan saat boot jika service bawaan `podman-restart.service` aktif.

**Rootless (user biasa):**

```bash
systemctl --user enable --now podman-restart.service
loginctl enable-linger "$USER"
```

`enable-linger` membuat service user tetap berjalan walaupun tidak ada sesi login.

**Rootful (root):**

```bash
sudo systemctl enable --now podman-restart.service
```

Pastikan service lain juga aktif:

```bash
systemctl is-enabled mariadb       # Expected: enabled
systemctl is-enabled cloudflared   # Expected: enabled (jika memakai Tunnel)
systemctl is-enabled nginx         # jika memakai Nginx
systemctl is-enabled apache2       # jika memakai Apache
```

> **Catatan:** policy `restart: always` dipilih (bukan `unless-stopped`) karena `podman-restart.service` bawaan hanya menjamin container dengan policy `always`.

## 6.3 Tes reboot

Satu kali tes reboot jauh lebih meyakinkan daripada membaca konfigurasi:

```bash
sudo reboot
```

Setelah server hidup lagi (sekitar 1 menit), masuk SSH dan cek:

```bash
podman ps
curl -I http://127.0.0.1:<APP_PORT>
curl -I https://<APP_DOMAIN>
```

Jika container tidak hidup, lihat [Troubleshooting](09-troubleshooting.md#container-tidak-hidup-setelah-reboot).

## 6.4 Checklist akhir

> **Catatan:** checkbox di halaman file seperti ini hanya tampilan dan **tidak bisa diklik** (GitHub menampilkannya dalam keadaan nonaktif). Supaya bisa dicentang dan progresnya tersimpan, buka **Issues → New issue → Deployment checklist**. Template-nya ada di [`.github/ISSUE_TEMPLATE/deployment-checklist.md`](../.github/ISSUE_TEMPLATE/deployment-checklist.md), dan satu issue dipakai untuk satu kali deployment.

**Lokal dan GitHub**

- [ ] Container jalan di lokal dan fitur utama sudah dicoba
- [ ] `URL::forceScheme('https')` ada di `AppServiceProvider`
- [ ] `composer.lock`, `docker/`, `scripts/`, `docker-compose.yml`, `.env.example` sudah ter-commit
- [ ] `.env` **tidak** ter-commit

**Server**

- [ ] Podman, Podman Compose, dan MariaDB terpasang
- [ ] Firewall aktif, SSH diizinkan, `3306` dan `8000` tidak terbuka ke publik
- [ ] Database dan user database sudah dibuat
- [ ] Repo di-clone ke `/var/www/<APP_DOMAIN>`

**Environment**

- [ ] `.env` production tersedia, tidak ada placeholder `<...>` tersisa
- [ ] `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://<APP_DOMAIN>`
- [ ] `APP_KEY` terisi
- [ ] `APP_PORT` dan `CONTAINER_NAME` unik per project

**Container dan Laravel**

- [ ] `podman compose build` dan `up -d` berhasil, `podman ps` menunjukkan `Up`
- [ ] `vendor/autoload.php` ada
- [ ] `migrate --force`, `storage:link`, `optimize` berhasil
- [ ] `curl -I http://127.0.0.1:<APP_PORT>` menghasilkan `200`

**Domain dan HTTPS**

- [ ] Tunnel / Nginx / Apache mengarah ke `<APP_PORT>`
- [ ] DNS resolve dan `curl -I https://<APP_DOMAIN>` menghasilkan `200`
- [ ] CSS/JS dimuat lewat HTTPS

**Stabilitas**

- [ ] `podman-restart.service` aktif
- [ ] `cloudflared` enabled dan active (jika dipakai)
- [ ] Sudah dites dengan reboot

**Google OAuth (jika dipakai)**

- [ ] Redirect URI di `.env` dan Google Cloud Console sama persis

---

**Selanjutnya:** [7. Update dan Operasional →](07-update-dan-operasional.md)
