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
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  VolunteerTask copyWith({
    TaskStatus? status,
    String? assignedTo,
    DateTime? completedAt,
    double? matchScore,
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
      };

  factory VolunteerTask.fromMap(Map<String, dynamic> map) => VolunteerTask(
        id: map['id'],
        title: map['title'],
        description: map['description'],
        needType: map['needType'],
        location: map['location'],
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        ward: map['ward'],
        urgency: map['urgency'],
        requiredSkills: List<String>.from(map['requiredSkills']),
        estimatedPeopleAffected: map['estimatedPeopleAffected'],
        assignedTo: map['assignedTo'],
        status: TaskStatus.values.byName(map['status']),
        sdgTags: List<int>.from(map['sdgTags']),
        createdFromReportId: map['createdFromReportId'],
        ngoId: map['ngoId'],
        createdAt: DateTime.parse(map['createdAt']),
        completedAt: map['completedAt'] != null
            ? DateTime.parse(map['completedAt'])
            : null,
        matchScore: map['matchScore']?.toDouble(),
      );
}
