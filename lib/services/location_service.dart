import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/app_state.dart';

class LocationService {
  final AppState appState;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool isTracking = false;

  LocationService(this.appState);

  /// Requests permissions and initiates the privacy-first location stream
  Future<bool> toggleTracking() async {
    if (isTracking) {
      await _stopTracking();
      return false;
    } else {
      bool permissionGranted = await _startTracking();
      return permissionGranted;
    }
  }

  Future<bool> _startTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return false;
      }
    }

    isTracking = true;
    
    // Adaptive Accuracy: Default to High to balance battery vs precision
    final LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Only ping backend if volunteer moves at least 10 meters
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position? position) {
      if (position != null) {
        _sendLocationToBackend(position);
      }
    });
    
    return true;
  }

  Future<void> _stopTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    isTracking = false;
  }

  Future<void> _sendLocationToBackend(Position position) async {
    if (appState.apiClient == null || !appState.isAuthenticated) return;

    try {
      await appState.apiClient!.post(
        '/api/v1/location/update',
        {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': position.timestamp.toIso8601String(),
          // Hardcoded dummy skills for Phase 2 simulation; ideally pulled from actual AppState User Profile
          'skills': ['medical', 'rescue'] 
        },
      );
      if (kDebugMode) {
        print('Location streamed to backend: \${position.latitude}, \${position.longitude}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to stream location: \$e');
      }
    }
  }
}
