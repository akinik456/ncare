import 'package:geolocator/geolocator.dart';


class LocationService {
  static Future<Position?> getCurrentLocationSafe({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 20),
  }) async {
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!gpsEnabled) return null;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeLimit,
      );
    } catch (_) {
      return null;
    }
  }
}