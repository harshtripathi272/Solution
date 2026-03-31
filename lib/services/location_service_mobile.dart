// Mobile (Android/iOS) implementation using the geolocator plugin
import 'dart:async';
import 'package:geolocator/geolocator.dart';

Future<bool> checkAndRequestPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;

  LocationPermission perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  return perm != LocationPermission.denied &&
      perm != LocationPermission.deniedForever;
}

Stream<Map<String, double>> getPositionStream() {
  const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // only emit if moved ≥10m
  );

  return Geolocator.getPositionStream(locationSettings: settings).map(
    (pos) => {'lat': pos.latitude, 'lon': pos.longitude},
  );
}

Future<Map<String, double>> getCurrentPosition() async {
  final pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 10),
    ),
  );
  return {'lat': pos.latitude, 'lon': pos.longitude};
}
