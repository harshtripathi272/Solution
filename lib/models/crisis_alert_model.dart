import 'package:uuid/uuid.dart';

enum AlertSeverity { critical, high, moderate, low }

class CrisisAlert {
  final String id;
  final String prediction;
  final String affectedArea;
  final String ward;
  final double latitude;
  final double longitude;
  final AlertSeverity severity;
  final String dataSource;
  final List<String> preMobilizationTaskIds;
  final String? weatherData;
  final DateTime predictedDate;
  final DateTime createdAt;
  final bool isActive;

  CrisisAlert({
    String? id,
    required this.prediction,
    required this.affectedArea,
    required this.ward,
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.dataSource,
    this.preMobilizationTaskIds = const [],
    this.weatherData,
    required this.predictedDate,
    DateTime? createdAt,
    this.isActive = true,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'prediction': prediction,
        'affectedArea': affectedArea,
        'ward': ward,
        'latitude': latitude,
        'longitude': longitude,
        'severity': severity.name,
        'dataSource': dataSource,
        'preMobilizationTaskIds': preMobilizationTaskIds,
        'weatherData': weatherData,
        'predictedDate': predictedDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory CrisisAlert.fromMap(Map<String, dynamic> map) => CrisisAlert(
        id: map['id'],
        prediction: map['prediction'],
        affectedArea: map['affectedArea'],
        ward: map['ward'],
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        severity: AlertSeverity.values.byName(map['severity']),
        dataSource: map['dataSource'],
        preMobilizationTaskIds:
            List<String>.from(map['preMobilizationTaskIds'] ?? []),
        weatherData: map['weatherData'],
        predictedDate: DateTime.parse(map['predictedDate']),
        createdAt: DateTime.parse(map['createdAt']),
        isActive: map['isActive'] ?? true,
      );
}
