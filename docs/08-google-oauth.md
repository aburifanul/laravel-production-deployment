# 8. Google OAuth (Opsional)

> **Langkah 8 dari 8** · Sebelumnya: [7. Update dan Operasional](07-update-dan-operasional.md) · Berikutnya: [9. Troubleshooting](09-troubleshooting.md)

Lewati halaman ini jika aplikasi tidak memakai Google Login (Laravel Socialite).

Tujuan: login Google berjalan di production dengan redirect URI yang tepat.

## 8.1 Siapkan di Google Cloud Console

Buat OAuth Client (tipe **Web application**), lalu daftarkan **Authorized redirect URI**:

```text
https://<APP_DOMAIN>/auth/google/callback
```

Salin Client ID dan Client Secret.

## 8.2 Isi `.env` di server

```bash
cd /var/www/<APP_DOMAIN>
nano .env
```

```env
GOOGLE_CLIENT_ID=<isi dari Google Cloud Console>
GOOGLE_CLIENT_SECRET=<isi dari Google Cloud Console>
GOOGLE_REDIRECT_URI=https://<APP_DOMAIN>/auth/google/callback
```

Tulis redirect URI sebagai **nilai final**. Jangan memakai `"${APP_URL}/auth/google/callback"`: ekspansi variabel tidak dijamin berjalan pada konfigurasi ini, dan hasilnya redirect URI yang salah.

## 8.3 Terapkan perubahan

Container harus dibuat ulang karena `.env` berubah:

```bash
podman compose up -d --force-recreate

podman exec <CONTAINER_NAME> php artisan optimize:clear
podman exec <CONTAINER_NAME> php artisan optimize
```

## 8.4 Verifikasi

```bash
podman exec <CONTAINER_NAME> php artisan tinker --execute="dump(config('app.url')); dump(config('services.google.redirect'));"
```

Yang diharapkan:

```text
"https://<APP_DOMAIN>"
"https://<APP_DOMAIN>/auth/google/callback"
```

Lalu coba login Google dari `https://<APP_DOMAIN>`.

## 8.5 Hal yang sering salah

Redirect URI di `.env` dan di Google Cloud Console harus **sama persis**. Perbedaan kecil berikut membuat OAuth gagal:

| Perbedaan | Contoh |
|-----------|--------|
| Skema | `http://` vs `https://` |
| Subdomain | `www` vs non-www |
| Garis miring | trailing slash `/` di akhir |
| Path | `/auth/google/callback` vs `/login/google/callback` |

Error `400: invalid_request` hampir selalu berarti redirect URI tidak cocok. Detailnya ada di [Troubleshooting](09-troubleshooting.md#google-oauth-error-400-invalid_request).

> **Penting:** Client Secret hanya disimpan di `.env` server. Jangan commit ke GitHub.

---

**Selanjutnya:** [9. Troubleshooting →](09-troubleshooting.md)
