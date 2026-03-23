import 'package:uuid/uuid.dart';

enum ReportSource { camera, voice, text, whatsapp }

class FieldReport {
  final String id;
  final String ngoId;
  final String submittedBy;
  final String needType;
  final String description;
  final String location;
  final double latitude;
  final double longitude;
  final String urgency; // Critical, High, Medium, Low
  final int estimatedPeopleAffected;
  final ReportSource source;
  final String? imageUrl;
  final String? rawText;
  final Map<String, dynamic>? extractedData;
  final DateTime timestamp;
  final String ward;

  FieldReport({
    String? id,
    required this.ngoId,
    required this.submittedBy,
    required this.needType,
    required this.description,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.urgency,
    required this.estimatedPeopleAffected,
    required this.source,
    this.imageUrl,
    this.rawText,
    this.extractedData,
    DateTime? timestamp,
    required this.ward,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'ngoId': ngoId,
        'submittedBy': submittedBy,
        'needType': needType,
        'description': description,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'urgency': urgency,
        'estimatedPeopleAffected': estimatedPeopleAffected,
        'source': source.name,
        'imageUrl': imageUrl,
        'rawText': rawText,
        'extractedData': extractedData,
        'timestamp': timestamp.toIso8601String(),
        'ward': ward,
      };

  factory FieldReport.fromMap(Map<String, dynamic> map) => FieldReport(
        id: map['id'],
        ngoId: map['ngoId'],
        submittedBy: map['submittedBy'],
        needType: map['needType'],
        description: map['description'],
        location: map['location'],
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        urgency: map['urgency'],
        estimatedPeopleAffected: map['estimatedPeopleAffected'],
        source: ReportSource.values.byName(map['source']),
        imageUrl: map['imageUrl'],
        rawText: map['rawText'],
        extractedData: map['extractedData'],
        timestamp: DateTime.parse(map['timestamp']),
        ward: map['ward'],
      );
}
