import 'package:uuid/uuid.dart';

enum UserRole { ngoWorker, volunteer, coordinator }

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
    this.trustScore = 5.0,
    this.tasksCompleted = 0,
    this.totalHoursVolunteered = 0,
    this.isAvailable = true,
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
        trustScore: (map['trustScore'] ?? 5.0).toDouble(),
        tasksCompleted: map['tasksCompleted'] ?? 0,
        totalHoursVolunteered: map['totalHoursVolunteered'] ?? 0,
        isAvailable: map['isAvailable'] ?? true,
        createdAt: DateTime.parse(map['createdAt']),
      );
}
