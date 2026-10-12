import 'dart:convert';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class LocationException implements Exception {
  final String message;
  LocationException(this.message);

  @override
  String toString() => message;
}

/// Result of matching a position against the company's configured
/// [location_zones] on the backend.
class ZoneMatchResult {
  /// The matched zone's real `zone_name`, or a reverse-geocoded address
  /// when the position doesn't fall inside any configured zone.
  final String zoneName;

  /// The project linked to the matched zone, if any. Only ever set when
  /// [matchedZone] is true.
  final String? projectName;

  /// Whether [zoneName] came from an actual configured zone (true) or a
  /// geocoded/fallback address (false).
  final bool matchedZone;

  /// Zone control: the company only allows check-in / check-out inside one
  /// of its zones. False when the backend couldn't be reached (the backend
  /// still enforces it on the check-in / check-out call).
  final bool restrictToZones;

  /// Whether the company has at least one active zone.
  final bool hasZones;

  const ZoneMatchResult({
    required this.zoneName,
    this.projectName,
    required this.matchedZone,
    this.restrictToZones = false,
    this.hasZones = false,
  });

  /// Why check-in / check-out isn't allowed at this position, or null.
  String? get zoneProblem {
    if (!restrictToZones || matchedZone) return null;
    if (!hasZones) {
      return 'Your company only allows check-in and check-out inside a work '
          'zone, but no work zones are set up yet. Please contact your admin.';
    }
    return 'You are outside your work zone. Check-in and check-out are only '
        'allowed inside a work zone. Please move inside the zone and try again.';
  }
}

class LocationService {
  static Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        'Location is turned off. Please turn on location (GPS) on your phone and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException(
          'This app needs your location to mark attendance. Please tap Allow when asked.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Location access is turned off for this app. Please allow location in your phone Settings, then try again.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Matches [latitude]/[longitude] against the company's configured
  /// geofence zones on the backend (`GET /zones-advance`). If the position
  /// falls inside an active zone, returns that zone's real `zone_name`
  /// along with the `project_name` linked to it. Otherwise falls back to
  /// the backend's reverse-geocoded address, and finally to on-device
  /// reverse geocoding if the backend can't be reached at all.
  static Future<ZoneMatchResult> resolveZone({
    required String companyCode,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri =
          Uri.parse(
            '${ApiConfig.baseHost}/api/v1/admin_and_super_admin/zones-advance',
          ).replace(
            queryParameters: {
              'company_code': companyCode,
              'latitude': '$latitude',
              'longitude': '$longitude',
            },
          );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final currentLocation =
            body['current_location'] as Map<String, dynamic>?;
        final restrictToZones = body['restrict_to_zones'] == true;
        final zones = body['zones'];
        final hasZones = zones is List &&
            zones.any((z) => z is Map && z['is_active'] != false);

        if (currentLocation?['matched'] == true) {
          final zone = currentLocation!['zone'] as Map<String, dynamic>?;
          final zoneName = zone?['zone_name']?.toString().trim();
          if (zoneName != null && zoneName.isNotEmpty) {
            final projectName = zone?['project_name']?.toString().trim();
            return ZoneMatchResult(
              zoneName: zoneName,
              projectName: (projectName == null || projectName.isEmpty)
                  ? null
                  : projectName,
              matchedZone: true,
              restrictToZones: restrictToZones,
              hasZones: hasZones,
            );
          }
        }

        final geocoded = currentLocation?['geocoded_address']
            ?.toString()
            .trim();
        if (geocoded != null && geocoded.isNotEmpty) {
          return ZoneMatchResult(
            zoneName: geocoded,
            matchedZone: false,
            restrictToZones: restrictToZones,
            hasZones: hasZones,
          );
        }
        if (restrictToZones) {
          return ZoneMatchResult(
            zoneName: await resolveZoneName(latitude, longitude),
            matchedZone: false,
            restrictToZones: true,
            hasZones: hasZones,
          );
        }
      }
    } catch (_) {
      // Backend unreachable / bad response — fall through to on-device
      // reverse geocoding below rather than blocking check-in on it.
    }

    final fallbackName = await resolveZoneName(latitude, longitude);
    return ZoneMatchResult(zoneName: fallbackName, matchedZone: false);
  }

  static Future<String> resolveZoneName(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        return '$latitude,$longitude';
      }

      final place = placemarks.first;
      final parts = [
        place.subLocality,
        place.locality,
        place.administrativeArea,
      ].where((p) => p != null && p.trim().isNotEmpty).toList();

      return parts.isEmpty ? '$latitude,$longitude' : parts.join(', ');
    } catch (_) {
      return '$latitude,$longitude';
    }
  }
}
