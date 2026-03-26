// Web implementation using dart:html standard Geolocation API
// This avoids the geolocator package on Chrome which crashes DDC.
import 'dart:async';
import 'dart:html' as html;

Future<bool> checkAndRequestPermission() async {
  // On web, permission is requested implicitly via getCurrentPosition / watchPosition
  return true;
}

Stream<Map<String, double>> getPositionStream() {
  final controller = StreamController<Map<String, double>>();

  html.window.navigator.geolocation.watchPosition(
    enableHighAccuracy: true,
    timeout: const Duration(seconds: 30),
  ).listen(
    (html.Geoposition pos) {
      controller.add({
        'lat': pos.coords!.latitude!.toDouble(),
        'lon': pos.coords!.longitude!.toDouble(),
      });
    },
    onError: (e) => controller.addError(e),
  );

  return controller.stream;
}
