# 5. Hubungkan Domain

> **Langkah 5 dari 8** · Sebelumnya: [4. Deploy di Server](04-deploy-server.md) · Berikutnya: [6. Verifikasi dan Autostart](06-verifikasi-autostart.md)

Tujuan: `https://<APP_DOMAIN>` bisa dibuka dari internet. Pilih **satu** dari tiga cara. Prasyarat: origin `curl -I http://127.0.0.1:<APP_PORT>` sudah `200` ([langkah 4.7](04-deploy-server.md#47-cek-origin)).

| Cara | Alur | Butuh Nginx/Apache? | Port 80/443 dibuka? |
|------|------|:-------------------:|:-------------------:|
| [Opsi 1: Cloudflare Tunnel](#opsi-1-cloudflare-tunnel) (disarankan) | Cloudflare → Tunnel → Container | Tidak | Tidak |
| [Opsi 2: Nginx](#opsi-2-nginx) | Cloudflare → Nginx → Container | Ya | Ya |
| [Opsi 3: Apache](#opsi-3-apache) | Cloudflare → Apache → Container | Ya | Ya |

## Opsi 1: Cloudflare Tunnel

Tidak perlu Nginx/Apache dan tidak perlu membuka port di server. Prasyarat: service `cloudflared` sudah aktif ([langkah 3.5](03-siapkan-server.md#35-cloudflare-tunnel)).

Tambahkan hostname:

```text
Cloudflare Zero Trust
→ Networks
→ Tunnels
→ pilih Tunnel
→ Configure
→ Public Hostnames
→ Add a public hostname
```

Isi:

| Field | Nilai | Contoh |
|-------|-------|--------|
| Subdomain | `<PROJECT_ALIAS>` | `akademik` |
| Domain | `<ROOT_DOMAIN>` | `example.com` |
| Type | `HTTP` | `HTTP` |
| URL | `localhost:<APP_PORT>` | `localhost:8000` |

Hasilnya:

```text
https://akademik.example.com → Cloudflare Tunnel → localhost:8000
```

Jika tunnel gagal:

```bash
systemctl status cloudflared --no-pager
journalctl -u cloudflared -n 100 --no-pager
```

<details>
<summary><b>DNS manual (jika record tidak dibuat otomatis)</b></summary>

Jika route dibuat lewat Zero Trust, DNS biasanya dibuat otomatis. Jika perlu manual:

| Field | Nilai |
|-------|-------|
| Type | `CNAME` |
| Name | `<PROJECT_ALIAS>` |
| Target | `<TUNNEL_UUID>.cfargotunnel.com` |
| Proxy status | Proxied |

```bash
dig <APP_DOMAIN>
```

</details>

## Opsi 2: Nginx

Install dan buka port web:

```bash
sudo apt install -y nginx
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Buat virtual host:

```bash
sudo nano /etc/nginx/sites-available/<APP_DOMAIN>.conf
```

```nginx
server {
    listen 80;

    server_name <APP_DOMAIN>;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:<APP_PORT>;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Contoh jika port `8000`: `proxy_pass http://127.0.0.1:8000;`

Aktifkan:

```bash
sudo ln -s /etc/nginx/sites-available/<APP_DOMAIN>.conf /etc/nginx/sites-enabled/
sudo nginx -t
```

Jika muncul `syntax is ok` dan `test is successful`:

```bash
sudo systemctl reload nginx
```

Test dari server:

```bash
curl -I -H "Host: <APP_DOMAIN>" http://127.0.0.1
```

## Opsi 3: Apache

Install, buka port web, dan aktifkan module:

```bash
sudo apt install -y apache2
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo a2enmod proxy proxy_http headers
sudo systemctl restart apache2
```

Buat virtual host:

```bash
sudo nano /etc/apache2/sites-available/<APP_DOMAIN>.conf
```

```apache
<VirtualHost *:80>

    ServerName <APP_DOMAIN>

    ProxyPreserveHost On

    ProxyPass / http://127.0.0.1:<APP_PORT>/
    ProxyPassReverse / http://127.0.0.1:<APP_PORT>/

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

    ErrorLog ${APACHE_LOG_DIR}/<PROJECT_ALIAS>_error.log
    CustomLog ${APACHE_LOG_DIR}/<PROJECT_ALIAS>_access.log combined

</VirtualHost>
```

Aktifkan:

```bash
sudo a2ensite <APP_DOMAIN>.conf
sudo apache2ctl configtest
```

Harus menampilkan `Syntax OK`, lalu:

```bash
sudo systemctl reload apache2
```

Test dari server:

```bash
curl -I -H "Host: <APP_DOMAIN>" http://127.0.0.1
```

## DNS dan SSL untuk Opsi 2 dan 3

Arahkan domain ke IP server lewat Cloudflare:

| Field | Nilai |
|-------|-------|
| Type | `A` |
| Name | `<PROJECT_ALIAS>` |
| Content | `<SERVER_IP>` |
| Proxy status | Proxied |

Karena Nginx/Apache di contoh ini hanya listen di port 80, atur mode SSL/TLS Cloudflare yang sesuai (misalnya **Flexible**), atau pasang Origin Certificate di server dan gunakan mode **Full**.

## Cek hasil

```bash
curl -I https://<APP_DOMAIN>
```

Yang diharapkan `HTTP/2 200`. Lalu buka `https://<APP_DOMAIN>` di browser dan periksa bahwa CSS/JS dimuat lewat HTTPS.

Jika gagal, periksa berurutan:

```text
DNS → Cloudflare → Tunnel/Proxy → Port origin → Container → Laravel
```

Detailnya ada di [Troubleshooting](09-troubleshooting.md#cloudflare-origin-berhasil-domain-gagal).

---

**Selanjutnya:** [6. Verifikasi dan Autostart →](06-verifikasi-autostart.md)
