# 2. Push ke GitHub

> **Langkah 2 dari 8** · Sebelumnya: [1. Persiapan Lokal](01-persiapan-lokal.md) · Berikutnya: [3. Siapkan Server](03-siapkan-server.md)

Tujuan: kode project (termasuk file container) ada di GitHub, **tanpa** secret. Server nanti mengambil kode dari sini lewat `git clone` dan `git pull`.

## Isi halaman

- [2.1 Buat repository](#21-buat-repository)
- [2.2 Pastikan `.gitignore` aman](#22-pastikan-gitignore-aman)
- [2.3 Commit dan push](#23-commit-dan-push)
- [2.4 Cek `.env` tidak ikut](#24-cek-env-tidak-ikut)
- [2.5 Apa yang harus ada di repo](#25-apa-yang-harus-ada-di-repo)

## 2.1 Buat repository

Di GitHub: **New repository**, isi nama `<REPO_NAME>`, pilih Private atau Public. Jika project sudah punya riwayat Git sendiri, jangan centang "Add a README", "Add .gitignore", atau "Choose a license" supaya repo masih kosong.

## 2.2 Pastikan `.gitignore` aman

`.gitignore` bawaan Laravel sudah mengecualikan `.env`. Pastikan baris-baris berikut ada:

```text
.env
.env.*
!.env.example
/vendor/
/node_modules/
/public/build/
/public/hot
/storage/*.key
/storage/logs/*
/storage/framework/cache/*
/storage/framework/sessions/*
/storage/framework/views/*
```

`!.env.example` penting: `.env` **tidak** boleh ter-commit, tetapi `.env.example` **harus** ikut karena dipakai sebagai template di server.

## 2.3 Commit dan push

Dari root project:

```bash
git init -b main          # lewati jika folder ini sudah repo git
git add .
git status                # periksa daftar file, pastikan .env TIDAK ada
git commit -m "Add Docker setup with FrankenPHP and Caddy"
git remote add origin git@github.com:<GITHUB_USER>/<REPO_NAME>.git
git push -u origin main
```

Jika belum memakai SSH key di GitHub, gunakan URL HTTPS:

```bash
git remote add origin https://github.com/<GITHUB_USER>/<REPO_NAME>.git
```

Kalau `remote origin` sudah ada dan salah, perbaiki dengan:

```bash
git remote set-url origin git@github.com:<GITHUB_USER>/<REPO_NAME>.git
```

## 2.4 Cek `.env` tidak ikut

```bash
git ls-files | grep -E '^\.env$' || echo "OK: .env tidak ter-commit"
```

Harus menampilkan `OK: .env tidak ter-commit`. Untuk memastikan tidak ada secret yang pernah masuk ke riwayat commit:

```bash
git log --all --oneline -- .env
```

Tidak boleh ada output.

> **Penting:** jangan pernah commit `.env`, `APP_KEY`, password database, Google Client Secret, atau token Cloudflare. Jika sudah terlanjur ter-commit, ganti secret-nya terlebih dahulu, lalu bersihkan riwayat Git, baru lanjut.

## 2.5 Apa yang harus ada di repo

| File / folder | Wajib | Alasan |
|---------------|:-----:|--------|
| `composer.json`, `composer.lock` | Ya | server menjalankan `composer install` dari lock file |
| `docker/` | Ya | Dockerfile, Caddyfile, php.ini |
| `docker-compose.yml` | Ya | definisi container |
| `.dockerignore` | Ya | mengatur isi build context |
| `.env.example` | Ya | template environment |
| `scripts/deploy.sh` | Ya | script update di server |
| `package.json`, `package-lock.json` | Jika memakai Vite | `npm ci` membutuhkan lock file |
| `.env` | **Tidak** | berisi secret |
| `vendor/`, `node_modules/`, `public/build/` | **Tidak** | dibuat ulang di server |

---

**Selanjutnya:** [3. Siapkan Server →](03-siapkan-server.md)
