---
name: Deployment checklist
about: Checklist deploy Laravel ke server. Centang satu per satu, progres tersimpan di issue.
title: "Deploy: nama-project"
---

## Info deployment

- Project:
- Domain:
- Server / IP:
- Cara hubung domain (Tunnel / Nginx / Apache):

## Checklist

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

## Catatan

Tulis kendala, output error, atau hal yang perlu diingat di sini.
