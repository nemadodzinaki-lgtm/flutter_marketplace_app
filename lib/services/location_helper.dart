import 'package:geolocator/geolocator.dart';

/// Gets location only after an explicit user action. Never persist raw GPS.
class MarketplaceLocation {
  static Future<Position> currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Location services are off. Turn them on in your device settings.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is not allowed. Enable it in your device or browser settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  /// Snap to ~2 km x ~2 km grid in South Africa. This is only approximate.
  static double approximateCoordinate(double coordinate) {
    return (coordinate / 0.02).round() * 0.02;
  }

  static bool validCoordinates(double latitude, double longitude) {
    return latitude.isFinite && longitude.isFinite &&
        latitude >= -90 && latitude <= 90 &&
        longitude >= -180 && longitude <= 180;
  }
}
