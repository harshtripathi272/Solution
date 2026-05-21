import 'package:uuid/uuid.dart';

enum UserRole { platformAdmin, ngoAdmin, ngoWorker, volunteer, coordinator }

class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? ngoId;
  final String? phone;
  final List<String> skills;
  final String? location;
  final double? latitude;
  final double? longitude;
  final double trustScore;
  final int tasksCompleted;
  final int totalHoursVolunteered;
  final bool isAvailable;
  final bool isIndependent;
  final DateTime createdAt;

  AppUser({
    String? id,
    required this.name,
    required this.email,
    required this.role,
    this.ngoId,
    this.phone,
    this.skills = const [],
    this.location,
    this.latitude,
    this.longitude,
    this.trustScore = 4.0,
    this.tasksCompleted = 0,
    this.totalHoursVolunteered = 0,
    this.isAvailable = true,
    this.isIndependent = false,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'ngoId': ngoId,
        'phone': phone,
        'skills': skills,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'trustScore': trustScore,
        'tasksCompleted': tasksCompleted,
        'totalHoursVolunteered': totalHoursVolunteered,
        'isAvailable': isAvailable,
        'isIndependent': isIndependent,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'],
        name: map['name'],
        email: map['email'],
        role: UserRole.values.byName(map['role']),
        ngoId: map['ngoId'],
        phone: map['phone'],
        skills: List<String>.from(map['skills'] ?? []),
        location: map['location'],
        latitude: map['latitude']?.toDouble(),
        longitude: map['longitude']?.toDouble(),
        trustScore: (map['trust_score'] ?? map['trustScore'] ?? 4.0).toDouble(),
        tasksCompleted: map['tasksCompleted'] ?? 0,
        totalHoursVolunteered: map['totalHoursVolunteered'] ?? 0,
        isAvailable: map['isAvailable'] ?? true,
        isIndependent: map['isIndependent'] ?? map['is_independent'] ?? false,
        createdAt: DateTime.parse(map['createdAt']),
      );

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    String? ngoId,
    String? phone,
    List<String>? skills,
    String? location,
    double? latitude,
    double? longitude,
    double? trustScore,
    int? tasksCompleted,
    int? totalHoursVolunteered,
    bool? isAvailable,
    bool? isIndependent,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      ngoId: ngoId ?? this.ngoId,
      phone: phone ?? this.phone,
      skills: skills ?? this.skills,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      trustScore: trustScore ?? this.trustScore,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
      totalHoursVolunteered: totalHoursVolunteered ?? this.totalHoursVolunteered,
      isAvailable: isAvailable ?? this.isAvailable,
      isIndependent: isIndependent ?? this.isIndependent,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
