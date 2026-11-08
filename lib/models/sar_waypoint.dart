import 'dart:convert';
import 'package:flutter/material.dart';

enum WaypointCategory {
  victim,
  rendezvous,
  water,
  hazard,
  camp,
  custom,
}

class SarWaypoint {
  final String id;
  final String name;
  final WaypointCategory category;
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime createdAt;
  final String createdBy;
  final String? notes;

  const SarWaypoint({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.createdAt,
    required this.createdBy,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
      'notes': notes,
    };
  }

  factory SarWaypoint.fromMap(Map<String, dynamic> map) {
    return SarWaypoint(
      id: map['id'] as String,
      name: map['name'] as String,
      category: WaypointCategory.values.firstWhere(
        (c) => c.name == (map['category'] as String? ?? 'custom'),
        orElse: () => WaypointCategory.custom,
      ),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      createdBy: map['created_by'] as String? ?? 'ANON',
      notes: map['notes'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory SarWaypoint.fromJson(String source) =>
      SarWaypoint.fromMap(json.decode(source) as Map<String, dynamic>);

  String get categoryLabel {
    switch (category) {
      case WaypointCategory.victim:
        return 'Korban / Survivor';
      case WaypointCategory.rendezvous:
        return 'Titik Kumpul / RV';
      case WaypointCategory.water:
        return 'Logistik & Air';
      case WaypointCategory.hazard:
        return 'Zona Bahaya / Rintangan';
      case WaypointCategory.camp:
        return 'Posko Aju SAR';
      case WaypointCategory.custom:
        return 'Titik Taktis';
    }
  }

  Color get categoryColor {
    switch (category) {
      case WaypointCategory.victim:
        return const Color(0xFFFF1744); // Merah terang
      case WaypointCategory.rendezvous:
        return const Color(0xFF00E676); // Hijau taktis
      case WaypointCategory.water:
        return const Color(0xFF00E5FF); // Sian air
      case WaypointCategory.hazard:
        return const Color(0xFFFF9100); // Oranye peringatan
      case WaypointCategory.camp:
        return const Color(0xFFFFD600); // Kuning posko
      case WaypointCategory.custom:
        return const Color(0xFFB388FF); // Ungu taktis
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case WaypointCategory.victim:
        return Icons.person_pin_circle_rounded;
      case WaypointCategory.rendezvous:
        return Icons.flag_rounded;
      case WaypointCategory.water:
        return Icons.water_drop_rounded;
      case WaypointCategory.hazard:
        return Icons.warning_rounded;
      case WaypointCategory.camp:
        return Icons.holiday_village_rounded;
      case WaypointCategory.custom:
        return Icons.location_on_rounded;
    }
  }
}
