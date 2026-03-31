class HeatmapPoint {
  final double latitude;
  final double longitude;
  final double severity;
  final String needType;
  final int populationAffected;
  final double confidence;
  final DateTime timestamp;
  final String geohash;
  final Map<String, int> needTypeBreakdown;
  final int sourceCount;

  HeatmapPoint({
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.needType,
    required this.populationAffected,
    required this.confidence,
    required this.timestamp,
    required this.geohash,
    required this.needTypeBreakdown,
    required this.sourceCount,
  });

  factory HeatmapPoint.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] ?? {};
    final timestamp = properties['last_updated'] != null
        ? DateTime.tryParse(properties['last_updated'] as String) ?? DateTime.now()
        : DateTime.now();

    return HeatmapPoint(
      latitude: double.tryParse(properties['latitude']?.toString() ?? '0') ?? 0.0,
      longitude: double.tryParse(properties['longitude']?.toString() ?? '0') ?? 0.0,
      severity: double.tryParse(properties['severity']?.toString() ?? '0') ?? 0.0,
      needType: (properties['need_type'] ?? 'other').toString().toLowerCase(),
      populationAffected: int.tryParse(properties['population_affected']?.toString() ?? '0') ?? 0,
      confidence: double.tryParse(properties['confidence']?.toString() ?? '0.5') ?? 0.5,
      timestamp: timestamp,
      geohash: (properties['geohash'] ?? '').toString(),
      needTypeBreakdown: Map<String, int>.from(
        (properties['need_type_breakdown'] as Map<dynamic, dynamic>?)?.cast<String, int>() ?? {},
      ),
      sourceCount: int.tryParse(properties['source_count']?.toString() ?? '1') ?? 1,
    );
  }

  /// Compute weighted intensity for heatmap visualization
  /// Formula: severity * (population_affected / 1000), clamped to [0, 1]
  double get weightedIntensity {
    final weighted = severity * (populationAffected / 1000);
    return weighted.clamp(0.0, 1.0);
  }

  /// Human-readable severity classification
  String get severityLabel {
    if (severity >= 0.8) return 'Extreme';
    if (severity >= 0.6) return 'Severe';
    if (severity >= 0.4) return 'Moderate';
    if (severity >= 0.2) return 'Stressed';
    return 'Minimal';
  }

  @override
  String toString() =>
      'HeatmapPoint(lat: $latitude, lon: $longitude, severity: $severity, need: $needType, pop: $populationAffected)';
}

class HeatmapException implements Exception {
  final String message;
  final String? messageHi;

  HeatmapException(this.message, {this.messageHi});

  @override
  String toString() => message;
}
