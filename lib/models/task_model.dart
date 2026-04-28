import 'package:uuid/uuid.dart';

enum TaskStatus { open, assigned, inProgress, completed, cancelled }

class VolunteerTask {
  final String id;
  final String title;
  final String description;
  final String needType;
  final String location;
  final double latitude;
  final double longitude;
  final String ward;
  final String urgency;
  final List<String> requiredSkills;
  final int estimatedPeopleAffected;
  final String? assignedTo;
  final TaskStatus status;
  final List<int> sdgTags;
  final String? createdFromReportId;
  final String ngoId;
  final DateTime createdAt;
  final DateTime? completedAt;
  final double? matchScore;
  /// Distance from search anchor in km (when API provides it).
  final double? distanceKm;

  VolunteerTask({
    String? id,
    required this.title,
    required this.description,
    required this.needType,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.ward,
    required this.urgency,
    required this.requiredSkills,
    required this.estimatedPeopleAffected,
    this.assignedTo,
    this.status = TaskStatus.open,
    required this.sdgTags,
    this.createdFromReportId,
    required this.ngoId,
    DateTime? createdAt,
    this.completedAt,
    this.matchScore,
    this.distanceKm,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  VolunteerTask copyWith({
    TaskStatus? status,
    String? assignedTo,
    DateTime? completedAt,
    double? matchScore,
    double? distanceKm,
  }) {
    return VolunteerTask(
      id: id,
      title: title,
      description: description,
      needType: needType,
      location: location,
      latitude: latitude,
      longitude: longitude,
      ward: ward,
      urgency: urgency,
      requiredSkills: requiredSkills,
      estimatedPeopleAffected: estimatedPeopleAffected,
      assignedTo: assignedTo ?? this.assignedTo,
      status: status ?? this.status,
      sdgTags: sdgTags,
      createdFromReportId: createdFromReportId,
      ngoId: ngoId,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      matchScore: matchScore ?? this.matchScore,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'needType': needType,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'ward': ward,
    'urgency': urgency,
    'requiredSkills': requiredSkills,
    'estimatedPeopleAffected': estimatedPeopleAffected,
    'assignedTo': assignedTo,
    'status': status.name,
    'sdgTags': sdgTags,
    'createdFromReportId': createdFromReportId,
    'ngoId': ngoId,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'matchScore': matchScore,
    'distanceKm': distanceKm,
  };

  factory VolunteerTask.fromMap(Map<String, dynamic> map) => VolunteerTask(
    id: (map['id'] ?? map['task_id'])?.toString(),
    title: (map['title'] ?? map['taskTitle'] ?? 'Historical context task')
        .toString(),
    description: (map['description'] ?? '').toString(),
    needType: (map['needType'] ?? map['need_type'] ?? 'other').toString(),
    location: (map['location'] ?? map['community_name'] ?? '').toString(),
    latitude: ((map['latitude'] ?? map['lat']) as num?)?.toDouble() ?? 0.0,
    longitude: ((map['longitude'] ?? map['lon']) as num?)?.toDouble() ?? 0.0,
    ward: (map['ward'] ?? map['community_name'] ?? '').toString(),
    urgency: (map['urgency'] ?? map['severity_classification'] ?? 'Moderate')
        .toString(),
    requiredSkills: List<String>.from(
      map['requiredSkills'] ?? map['required_skills'] ?? const [],
    ),
    estimatedPeopleAffected:
        ((map['estimatedPeopleAffected'] ?? map['population_affected'] ?? 0)
                as num)
            .toInt(),
    assignedTo: map['assignedTo']?.toString(),
    status: TaskStatus.values.byName((map['status'] ?? 'open').toString()),
    sdgTags: List<int>.from(map['sdgTags'] ?? map['sdg_tags'] ?? const []),
    createdFromReportId:
        (map['createdFromReportId'] ?? map['created_from_report_id'])
            ?.toString(),
    ngoId: (map['ngoId'] ?? map['ngo_id'] ?? map['community_id'] ?? 'community')
        .toString(),
    createdAt:
        DateTime.tryParse(
          (map['createdAt'] ?? map['created_at'] ?? '').toString(),
        ) ??
        DateTime.now(),
    completedAt: map['completedAt'] != null
        ? DateTime.tryParse(map['completedAt'].toString())
        : null,
    matchScore:
        (map['matchScore'] ?? map['priority'] ?? map['composite_urgency'])
            is num
        ? ((map['matchScore'] ?? map['priority'] ?? map['composite_urgency'])
                  as num)
              .toDouble()
        : double.tryParse(
            (map['matchScore'] ??
                    map['priority'] ??
                    map['composite_urgency'] ??
                    '')
                .toString(),
          ),
    distanceKm: map['distance_km'] != null || map['distanceKm'] != null
        ? ((map['distance_km'] ?? map['distanceKm']) as num?)?.toDouble()
        : null,
  );
}
