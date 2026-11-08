# SinyalNol --- Aplikasi Komunikasi Offline Android (Flutter)
**Versi:** 0.1 (Prototipe)  
**Platform Utama:** Android  
**Konsep:** Komunikasi teks dan berbagi lokasi tanpa akses internet, memanfaatkan hardware bawaan ponsel (Wi-Fi Hotspot / Subnet P2P, BLE, dan sensor GNSS/GPS).

---

## 📌 Prinsip & Batasan Fisik
1. **Kejujuran Status Pengiriman:** Status dibedakan secara tegas antara:
   - `queued`: Tersimpan di database lokal (menunggu jalur radio).
   - `relayed`: Terkirim ke perangkat tetangga / relay perantara.
   - `delivered`: Terkonfirmasi telah diterima oleh penerima akhir (ACK).
   - `failed`: Gagal atau waktu kedaluwarsa (TTL) habis.
2. **Batasan Frekuensi & Jarak:** Ponsel standar tidak dapat dimodifikasi dayanya hanya dengan software. Sasaran jarak 5–20 km diperlakukan sebagai **sasaran penelitian**, bukan klaim instan tanpa node relay perantara.
3. **Privasi & Koordinat:** Berbagi koordinat GPS dilakukan dengan izin dan opsi satu kali (*single-fetch*), bukan pelacakan latar belakang terus-menerus.
4. **Offline First:** Seluruh pesan dan log pengujian disimpan secara persisten di database SQLite (`sqflite`).

---

## 🏗️ Struktur Arsitektur
```
sinyal_nol/
├── lib/
│   ├── database/
│   │   └── local_db.dart             # SQLite: tabel messages & field_test_logs
│   ├── models/
│   │   ├── message_model.dart        # Model pesan: UUID, TTL, hop count, koordinat, status
│   │   └── peer_device.dart          # Model peer: id, name, address, RSSI, estimasi jarak
│   ├── services/
│   │   ├── connectivity_service.dart # Lapisan konektivitas terisolasi (UDP Discovery & TCP Socket P2P)
│   │   ├── message_service.dart      # Antrean, deduplikasi ID, TTL, Smart Relay
│   │   └── location_service.dart     # GPS GNSS offline, hitung jarak & arah kompas matematis
│   ├── providers/
│   │   └── app_provider.dart         # State management terpadu
│   ├── ui/
│   │   ├── theme/
│   │   │   └── app_theme.dart        # Tactical dark theme (Material 3)
│   │   ├── widgets/
│   │   │   ├── message_bubble.dart   # Bubble chat + status jujur + tag GPS
│   │   │   └── signal_indicator.dart # Banner radio lokal & jumlah peer
│   │   └── screens/
│   │       ├── home_nav_screen.dart  # Navigasi tab utama
│   │       ├── chat_list_screen.dart # Daftar percakapan publik & direct
│   │       ├── chat_conversation_screen.dart # Chat offline + lampirkan koordinat + navigasi kompas
│   │       ├── sos_screen.dart       # Broadcast darurat SOS + peringatan realistis
│   │       ├── radar_screen.dart     # Radar pemindai perangkat sekitar + simulator node
│   │       ├── field_test_screen.dart# Uji lapangan: jarak, RSSI, latency, medan, statistik
│   │       └── settings_screen.dart  # Konfigurasi Smart Relay, Hop limit, TTL, manajemen SQLite
│   └── main.dart
```

---

## 🚀 Cara Menjalankan & Menguji

### 1. Menjalankan di Perangkat Android / Emulator
```bash
cd c:\laragon\www\sinyal_nol
flutter run
```

### 2. Cara Menguji Komunikasi Dua Ponsel Tanpa Internet
1. Pada **Ponsel A**: Aktifkan fitur **Hotspot Portabel** (Tethering Wi-Fi) di setelan Android. Koneksi data seluler / internet boleh **dimatikan**.
2. Pada **Ponsel B**: Sambungkan ke Wi-Fi Hotspot dari Ponsel A.
3. Buka aplikasi **SinyalNol** di kedua ponsel:
   - Keduanya otomatis saling menemukan dalam beberapa detik melalui UDP broadcast beacon di port `8889`.
   - Perangkat akan muncul di tab **Radar** dan **Chat**.
   - Kirim pesan teks, lampirkan koordinat GPS, atau picu SOS.
   - Status pengiriman akan berpindah otomatis dari `queued` -> `delivered`.

### 3. Menguji pada 1 Perangkat / Emulator (Mode Simulasi)
1. Buka tab **Radar**.
2. Tekan tombol `(+)` di pojok kanan atas untuk menambahkan node pengujian (misal: "Posko-SAR-Alpha").
3. Anda dapat menguji chat langsung, simulasi hop count Smart Relay, dan pencatatan uji lapangan di tab **Uji Lapangan**.
