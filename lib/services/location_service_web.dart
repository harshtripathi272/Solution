// Web implementation using package:web Geolocation API
// This avoids the geolocator package on Chrome which crashes DDC.
import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart';

Future<bool> checkAndRequestPermission() async {
  // On web, permission is requested implicitly via getCurrentPosition / watchPosition
  return true;
}

Stream<Map<String, double>> getPositionStream() {
  final controller = StreamController<Map<String, double>>();

  void onSuccess(GeolocationPosition pos) {
    controller.add({
      'lat': pos.coords.latitude,
      'lon': pos.coords.longitude,
    });
  }

  void onError(GeolocationPositionError error) {
    controller.addError(error.message);
  }

  window.navigator.geolocation.watchPosition(
    onSuccess.toJS,
    onError.toJS,
    PositionOptions(
      enableHighAccuracy: true,
      timeout: 30000,
    ),
  );

  return controller.stream;
}

Future<Map<String, double>> getCurrentPosition() async {
  final completer = Completer<Map<String, double>>();

  void onSuccess(GeolocationPosition pos) {
    completer.complete({
      'lat': pos.coords.latitude,
      'lon': pos.coords.longitude,
    });
  }

  void onError(GeolocationPositionError error) {
    completer.completeError(error.message);
  }

  window.navigator.geolocation.getCurrentPosition(
    onSuccess.toJS,
    onError.toJS,
    PositionOptions(
      enableHighAccuracy: true,
      timeout: 10000,
    ),
  );

  return completer.future;
}
