import 'dart:async';
import 'package:flutter/foundation.dart';
import '../providers/app_state.dart';

// Conditionally import platform implementations
import 'location_service_web.dart' if (dart.library.io) 'location_service_mobile.dart'
    as platform_location;

/// Cross-platform adapter -- calls the Web HTML5 Geolocation API on browser
/// and [geolocator] on native. Either way, pushes updates to the FastAPI backend.
class LocationService {
  final AppState appState;
  bool _isTracking = false;
  Timer? _idleTimer;
  StreamSubscription? _subscription;

  LocationService(this.appState);

  bool get isTracking => _isTracking;

  /// Toggle tracking on or off. Returns new tracking state.
  Future<bool> toggleTracking() async {
    if (_isTracking) {
      await _stopTracking();
      return false;
    } else {
      return await _startTracking();
    }
  }

  Future<bool> _startTracking() async {
    final canTrack = await platform_location.checkAndRequestPermission();
    if (!canTrack) return false;

    _isTracking = true;

    _subscription = platform_location.getPositionStream().listen((coords) {
      _sendToBackend(coords['lat']!, coords['lon']!);
    });

    return true;
  }

  Future<void> _stopTracking() async {
    _idleTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    _isTracking = false;

    // Delete the user's location from Redis immediately on opt-out
    _revokeBackendLocation();
  }

  void _sendToBackend(double lat, double lon) async {
    if (appState.apiClient == null || !appState.isAuthenticated) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await appState.apiClient!.post('/api/v1/location/update', {
        'latitude': lat,
        'longitude': lon,
        'timestamp': now,
        'skills': [],      // Phase 3: fill from user profile
        'consent': true,
      });
    } catch (e) {
      if (kDebugMode) print('[LocationService] Failed to send: $e');
    }
  }

  void _revokeBackendLocation() async {
    try {
      await appState.apiClient?.get('/api/v1/location/revoke');
    } catch (_) {}
  }
}
