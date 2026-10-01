# 3. Siapkan Server atau VPS

> **Langkah 3 dari 8** · Sebelumnya: [2. Push ke GitHub](02-push-github.md) · Berikutnya: [4. Deploy di Server](04-deploy-server.md)

Tujuan: server punya semua yang dibutuhkan (Git, Podman, MariaDB, firewall). Langkah ini dilakukan **sekali** per server. Untuk project berikutnya di server yang sama, langsung ke langkah 4.

Contoh di sini untuk Ubuntu / Debian / Armbian.

## Isi halaman

- [3.1 Masuk ke server](#31-masuk-ke-server)
- [3.2 Install paket](#32-install-paket)
- [3.3 Firewall](#33-firewall)
- [3.4 Database di server](#34-database-di-server)
- [3.5 Cloudflare Tunnel](#35-cloudflare-tunnel)

## 3.1 Masuk ke server

```bash
ssh <SERVER_USER>@<SERVER_IP>
```

Gunakan user biasa yang punya akses `sudo`, bukan `root`. Jika baru punya `root`:

```bash
adduser <SERVER_USER>
usermod -aG sudo <SERVER_USER>
```

## 3.2 Install paket

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw podman podman-compose mariadb-server
```

Cek:

```bash
git --version
podman --version
podman-compose --version
sudo systemctl status mariadb --no-pager
```

Script `deploy.sh` memakai perintah `podman compose` (tanpa tanda hubung). Itu hanya pembungkus yang meneruskan ke `podman-compose`, jadi pastikan keduanya jalan:

```bash
podman compose version
```

> **Catatan:** contoh di panduan ini memakai user biasa (rootless Podman). Jika Podman dijalankan sebagai root, awali perintah `podman` dengan `sudo`. Jika `podman-compose` tidak tersedia di repo distro, pasang dengan `sudo apt install -y pipx && pipx install podman-compose`.

## 3.3 Firewall

Izinkan SSH **sebelum** mengaktifkan firewall supaya tidak terkunci:

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
```

Buka port web **hanya jika** memakai Nginx atau Apache:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Dengan Cloudflare Tunnel, port 80/443 tidak perlu dibuka.

| Port | Fungsi | Dibuka ke publik? |
|-----:|--------|:-----------------:|
| 22 | SSH | Ya |
| 80, 443 | Nginx / Apache | Hanya jika dipakai |
| 8000 (`APP_PORT`) | Container Laravel | **Tidak** (hanya `127.0.0.1`) |
| 3306 | MariaDB | **Tidak** |

## 3.4 Database di server

Buat password acak (hex, aman untuk `.env`):

```bash
openssl rand -hex 16
```

Simpan hasilnya sebagai `<DB_PASSWORD>`, lalu masuk ke MariaDB:

```bash
sudo mariadb
```

```sql
CREATE DATABASE <DB_NAME>;

CREATE USER '<DB_USER>'@'%' IDENTIFIED BY '<DB_PASSWORD>';

GRANT ALL PRIVILEGES ON <DB_NAME>.* TO '<DB_USER>'@'%';

FLUSH PRIVILEGES;

SHOW DATABASES;
```

Container harus bisa menjangkau MariaDB di host:

```bash
sudo ss -lntp | grep 3306
```

Jika hanya `127.0.0.1:3306`, ubah `bind-address` MariaDB (biasanya di `/etc/mysql/mariadb.conf.d/50-server.cnf`) menjadi `0.0.0.0`, lalu:

```bash
sudo systemctl restart mariadb
sudo ss -lntp | grep 3306
```

> **Peringatan:** port `3306` tidak boleh dibuka ke internet. Karena UFW sudah menolak koneksi masuk secara default, pastikan kamu tidak menjalankan `ufw allow 3306`. Jika UFW memblokir koneksi dari container ke MariaDB, lihat [Troubleshooting](09-troubleshooting.md#database-connection-refused).

## 3.5 Cloudflare Tunnel

Lewati bagian ini jika memakai Nginx atau Apache.

Jika server belum punya tunnel:

```text
Cloudflare Zero Trust
→ Networks
→ Tunnels
→ Create a tunnel
→ pilih Cloudflared
→ ikuti perintah install yang ditampilkan di dashboard
```

Setelah service `cloudflared` terpasang, cek:

```bash
systemctl status cloudflared --no-pager
systemctl is-enabled cloudflared    # Expected: enabled
systemctl is-active cloudflared     # Expected: active
```

Hostname untuk aplikasi ditambahkan di [langkah 5](05-hubungkan-domain.md).

<details>
<summary><b>Tunnel dengan token file (alternatif)</b></summary>

Jika `cloudflared` dijalankan dengan token yang disimpan di `/etc/cloudflared/token`, contoh `ExecStart` systemd:

```text
/usr/bin/cloudflared --no-autoupdate tunnel run --token-file /etc/cloudflared/token
```

Pada tunnel token-based (*remotely managed*), file `/etc/cloudflared/cert.pem` **tidak diperlukan** hanya untuk menjalankan tunnel.

</details>

---

**Selanjutnya:** [4. Deploy di Server →](04-deploy-server.md)
