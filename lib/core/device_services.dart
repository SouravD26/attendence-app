import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../data/models.dart';

/// A fix good enough to punch with, plus the human-readable address.
class PunchLocation {
  final Position position;
  final String address;

  const PunchLocation({required this.position, required this.address});
}

/// Why a location could not be resolved. Attendance may not be marked without
/// one, so each case has to tell the employee what to change.
enum LocationBlock {
  none,

  /// Location services are switched off device-wide.
  serviceDisabled,

  /// Permission refused this time; asking again is still allowed.
  permissionDenied,

  /// Refused permanently ("Don't ask again") — only Settings can undo it.
  permissionForever,

  /// Permitted and enabled, but no fix yet (indoors, or timed out).
  noFix,
}

/// Either a usable location, or the reason there isn't one.
class LocationResult {
  final PunchLocation? location;
  final LocationBlock block;

  const LocationResult({required this.location}) : block = LocationBlock.none;

  const LocationResult.blocked(this.block) : location = null;

  bool get ok => location != null;

  /// What to tell the employee, phrased as the thing they need to do.
  String get message {
    switch (block) {
      case LocationBlock.serviceDisabled:
        return 'Location is switched off. Turn on GPS to mark attendance.';
      case LocationBlock.permissionDenied:
        return 'This app needs location access to mark attendance.';
      case LocationBlock.permissionForever:
        return 'Location access is blocked. Enable it in Settings to mark '
            'attendance.';
      case LocationBlock.noFix:
        return 'Could not get a GPS fix. Move near a window and retry.';
      case LocationBlock.none:
        return '';
    }
  }

  /// Label for the button that resolves this block, if one can.
  String? get actionLabel {
    switch (block) {
      case LocationBlock.serviceDisabled:
        return 'Turn on GPS';
      case LocationBlock.permissionForever:
        return 'Open settings';
      case LocationBlock.permissionDenied:
      case LocationBlock.noFix:
      case LocationBlock.none:
        return null;
    }
  }
}

/// Wraps the two device capabilities a punch needs: where you are, and proof
/// it was you.
///
/// The selfie is captured by an in-app camera preview ([availableCameras] +
/// [CameraController] in the punch screen), never by handing the user off to
/// the system camera app — that kept the app in the background and let people
/// pick an existing photo on some devices.
class DeviceServices {
  /// Cached so the punch screen does not re-enumerate on every open.
  List<CameraDescription>? _cameras;

  /// geocoding 5.x exposes an instance API rather than top-level functions.
  ///
  /// Built lazily and defensively: the constructor reaches for the platform
  /// implementation, which throws where the plugin is not registered (widget
  /// tests, desktop). Reverse geocoding is a nicety, so a missing geocoder
  /// must degrade to coordinates rather than take the app down.
  Geocoding? _geocoder;
  bool _geocoderUnavailable = false;

  Geocoding? _resolveGeocoder() {
    if (_geocoderUnavailable) return null;
    try {
      return _geocoder ??= Geocoding();
    } catch (_) {
      _geocoderUnavailable = true;
      return null;
    }
  }

  /// Front camera when the device has one, else whatever it does have.
  Future<CameraDescription?> selfieCamera() async {
    try {
      _cameras ??= await availableCameras();
    } catch (_) {
      return null;
    }
    final cameras = _cameras!;
    if (cameras.isEmpty) return null;

    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.front) return c;
    }
    return cameras.first;
  }

  /// Resolves current position, or null if the user declined / GPS is off.
  Future<Position?> currentPosition() async =>
      (await resolveLocation()).location?.position;

  /// Resolves the position and, when it fails, *why* — the punch screen needs
  /// the reason to tell the employee which setting to change, since attendance
  /// cannot be marked without a fix.
  Future<LocationResult> resolveLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.blocked(LocationBlock.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.blocked(LocationBlock.permissionForever);
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.blocked(LocationBlock.permissionDenied);
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      // Indoors, or the fix timed out — retrying usually works.
      return const LocationResult.blocked(LocationBlock.noFix);
    }

    return LocationResult(
      location: PunchLocation(
        position: position,
        address: await describe(position),
      ),
    );
  }

  /// Position plus a street address. Reverse geocoding is best-effort: it needs
  /// network and can be slow, so a failure falls back to the coordinates rather
  /// than blocking the punch.
  Future<PunchLocation?> currentLocation() async =>
      (await resolveLocation()).location;

  /// Sends the user to the OS screen that fixes [block]. Returns false when
  /// there is nothing to open (the failure was a timeout, not a setting).
  Future<bool> openSettingsFor(LocationBlock block) async {
    switch (block) {
      case LocationBlock.serviceDisabled:
        return Geolocator.openLocationSettings();
      case LocationBlock.permissionForever:
        return Geolocator.openAppSettings();
      case LocationBlock.permissionDenied:
      case LocationBlock.noFix:
      case LocationBlock.none:
        return false;
    }
  }

  /// Best available description of a fix, never throwing.
  Future<String> describe(Position position) async {
    try {
      final geocoder = _resolveGeocoder();
      if (geocoder == null) return coordinatesOf(position);

      final places = await geocoder.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 8));

      if (places.isNotEmpty) {
        final line = _format(places.first);
        if (line.isNotEmpty) return line;
      }
    } catch (_) {
      // Offline or geocoder unavailable — coordinates still identify the spot.
    }
    return coordinatesOf(position);
  }

  static String coordinatesOf(Position p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  /// Builds a readable line, skipping the parts the geocoder left blank and
  /// dropping duplicates (locality and subAdministrativeArea often match).
  static String _format(Placemark p) {
    final parts = <String>[];
    for (final value in [
      p.name,
      p.subLocality,
      p.locality,
      p.administrativeArea,
      p.postalCode,
    ]) {
      final v = value?.trim();
      if (v == null || v.isEmpty) continue;
      if (parts.contains(v)) continue;
      parts.add(v);
    }
    return parts.take(4).join(', ');
  }

  /// Encodes a captured frame as the data URI the API expects in
  /// `selfie_image`.
  static Future<String> encodeSelfie(String path) async {
    final bytes = await File(path).readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  /// Builds the location half of a punch; the selfie is attached separately.
  Future<PunchContext> buildPunchContext() async {
    final located = await currentLocation();
    return PunchContext(
      latitude: located?.position.latitude,
      longitude: located?.position.longitude,
      accuracy: located?.position.accuracy,
      address: located?.address ?? 'Location unavailable',
    );
  }
}
