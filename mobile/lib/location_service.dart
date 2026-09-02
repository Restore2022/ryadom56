import 'package:geolocator/geolocator.dart';

class LocationFix {
  const LocationFix(this.lat, this.lon);
  final double lat;
  final double lon;
}

class LocationService {
  LocationService._();

  static Future<LocationFix?> current({bool requestPermission = true}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && requestPermission) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationFix(last.latitude, last.longitude);
        }
      } catch (_) {}
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)),
      );
      return LocationFix(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
