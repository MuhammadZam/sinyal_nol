import 'dart:math';
import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final DateTime timestamp;

  LocationResult({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    required this.timestamp,
  });

  String get formattedCoordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Periksa dan minta izin lokasi pengguna
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Ambil koordinat GPS satu kali (single-fetch) agar hemat baterai
  Future<LocationResult?> getCurrentLocation() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        timestamp: position.timestamp,
      );
    } catch (e) {
      // Fallback ke posisi terakhir yang diketahui jika satelit GNSS belum lock
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationResult(
            latitude: last.latitude,
            longitude: last.longitude,
            altitude: last.altitude,
            accuracy: last.accuracy,
            timestamp: last.timestamp,
          );
        }
      } catch (_) {}
      return null;
    }
  }

  /// Hitung jarak (dalam meter) antara dua titik koordinat
  double calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Hitung arah kompas / bearing (dalam derajat 0-360) ke titik target
  double calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    final lat1 = startLat * pi / 180.0;
    final lon1 = startLng * pi / 180.0;
    final lat2 = endLat * pi / 180.0;
    final lon2 = endLng * pi / 180.0;

    final dLon = lon2 - lon1;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final radians = atan2(y, x);
    final degrees = (radians * 180.0 / pi + 360.0) % 360.0;

    return degrees;
  }

  /// Nama arah mata angin (misal: "Utara", "Timur Laut", dll)
  String getCardinalDirection(double degrees) {
    const directions = ['U', 'TL', 'T', 'TG', 'S', 'BD', 'B', 'BL'];
    int index = ((degrees + 22.5) / 45.0).floor() % 8;
    return directions[index];
  }
}
