import 'dart:math' as math;

class TacticalCoords {
  static const double earthRadiusMeters = 6371000.0;
  static const double metersPerDegreeLat = 111319.9;

  /// Hitung jarak antara dua koordinat WGS84 menggunakan formula Haversine (meter)
  static double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Hitung sudut azimuth/bearing kompas dari titik awal ke titik target (0° - 359°)
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final deltaLambda = _degToRad(lon2 - lon1);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    final theta = math.atan2(y, x);
    final bearingDeg = (_radToDeg(theta) + 360) % 360;
    return bearingDeg;
  }

  /// Konversi derajat bearing ke arah mata angin militer (misal: "045° NE")
  static String bearingToCardinal(double bearing) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final index = ((bearing + 11.25) / 22.5).floor() % 16;
    final bStr = bearing.toStringAsFixed(0).padLeft(3, '0');
    return '$bStr° ${directions[index]}';
  }

  /// Format jarak dalam satuan taktis (meter atau kilometer)
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Proyeksi offset relatif (dx, dy dalam meter) dari titik acuan (centerLat, centerLon)
  /// dx: Timur (+), Barat (-)
  /// dy: Utara (- pada koordinat layar), Selatan (+)
  static math.Point<double> toMetersOffset(
    double targetLat,
    double targetLon,
    double centerLat,
    double centerLon,
  ) {
    final dLat = targetLat - centerLat;
    final dLon = targetLon - centerLon;

    final latMeters = dLat * metersPerDegreeLat;
    final lonMeters = dLon * metersPerDegreeLat * math.cos(_degToRad(centerLat));

    // Di canvas Flutter, Y bergerak ke bawah (Selatan), X bergerak ke kanan (Timur)
    return math.Point<double>(lonMeters, -latMeters);
  }

  /// Konversi WGS84 ke estimasi koordinat militer UTM (Universal Transverse Mercator)
  static String toUtmString(double lat, double lon) {
    if (lat < -80.0 || lat > 84.0) {
      return 'OUT OF UTM BOUNDS';
    }

    final zoneNumber = ((lon + 180) / 6).floor() + 1;
    final latZoneLetters = 'CDEFGHJKLMNPQRSTUVWX';
    final zoneLetterIdx = ((lat + 80) / 8).floor().clamp(0, 19);
    final zoneLetter = latZoneLetters[zoneLetterIdx];

    // Perhitungan Transverse Mercator disederhanakan untuk grid taktis
    final centralLon = (zoneNumber - 1) * 6 - 180 + 3;
    final dLon = _degToRad(lon - centralLon);
    final phi = _degToRad(lat);

    final falseEasting = 500000.0;
    final falseNorthing = lat < 0 ? 10000000.0 : 0.0;

    final easting = falseEasting + (earthRadiusMeters * dLon * math.cos(phi));
    final northing = falseNorthing + (earthRadiusMeters * phi);

    final eStr = easting.toStringAsFixed(0).padLeft(7, '0');
    final nStr = northing.toStringAsFixed(0).padLeft(7, '0');

    return '$zoneNumber$zoneLetter ${eStr}mE ${nStr}mN';
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
