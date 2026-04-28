import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/crisis_alert_model.dart';
import '../models/field_report_model.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';

class AppState extends ChangeNotifier {
  ApiClient? _apiClient;
  LocationService? _locationService;
  UserRole _currentRole = UserRole.volunteer;
  AppUser? _currentUser;
  bool _isLoadingUser = false;
  final bool _isLoading = false;
  String? _backendError;

  final List<FieldReport> _reports = [];
  final List<VolunteerTask> _tasks = [];
  final List<AppUser> _volunteers = [];
  final List<CrisisAlert> _crisisAlerts = [];

  int _currentNavIndex = 0;
  UserRole? _requestedRole;

  AppState() {
    _locationService = LocationService(this);
  }

  DateTime _parseBackendDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  List<String> _parseSkills(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  void _applyProfileData(Map<String, dynamic> data) {
    final roleValue = (data['role'] ?? 'volunteer').toString();
    final mappedRole = switch (roleValue) {
      'coordinator' => UserRole.coordinator,
      'ngo_worker' => UserRole.ngoWorker,
      _ => UserRole.volunteer,
    };

    _currentRole = mappedRole;
    _currentUser = AppUser(
      id: (data['uid'] ?? data['id'] ?? '').toString(),
      name: (data['name'] ?? 'User').toString(),
      email: (data['email'] ?? '').toString(),
      role: mappedRole,
      ngoId: data['organization_id']?.toString() ?? data['ngoId']?.toString(),
      phone: data['phone']?.toString(),
      skills: _parseSkills(data['skills']),
      location: data['location']?.toString(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      trustScore: (data['trust_score'] ?? data['trustScore'] ?? 5.0).toDouble(),
      tasksCompleted: (data['tasks_completed'] ?? data['tasksCompleted'] ?? 0) as int,
      totalHoursVolunteered:
          (data['total_hours_volunteered'] ?? data['totalHoursVolunteered'] ?? 0) as int,
      isAvailable: data['is_available'] ?? data['isAvailable'] ?? true,
      createdAt: _parseBackendDate(data['created_at'] ?? data['createdAt']),
    );
  }

  Future<void> refreshHistoricalTasks({
    double? latitude,
    double? longitude,
    double radiusKm = 30.0,
    int limit = 20,
  }) async {
    if (_apiClient == null || _currentUser == null) {
      return;
    }

    final isVolunteer = _currentRole == UserRole.volunteer;
    final queryParams = <String, String>{
      'radius_km': radiusKm.toString(),
      'limit': limit.toString(),
    };

    if (latitude != null && longitude != null) {
      queryParams['latitude'] = latitude.toString();
      queryParams['longitude'] = longitude.toString();
    } else if (isVolunteer) {
      return;
    }

    try {
      final uri = Uri.parse('${AppConstants.apiBaseUrl}/api/v1/tasks')
          .replace(queryParameters: queryParams);
      final response = await _apiClient!.get(
        uri.path + (uri.hasQuery ? '?${uri.query}' : ''),
      );
      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTasks = (data['tasks'] as List<dynamic>?) ?? const [];
      final tasks = rawTasks
          .whereType<Map<String, dynamic>>()
          .map(VolunteerTask.fromMap)
          .toList();

      _tasks
        ..clear()
        ..addAll(tasks);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[AppState] refreshHistoricalTasks failed: $e');
      }
    }
  }

  void setRequestedRole(UserRole role) {
    _requestedRole = role;
  }

  Future<void> initializeUser(User firebaseUser) async {
    final lastSignIn = firebaseUser.metadata.lastSignInTime;
    if (lastSignIn != null && DateTime.now().difference(lastSignIn).inHours >= 12) {
      await FirebaseAuth.instance.signOut();
      return;
    }

    _isLoadingUser = true;
    _backendError = null;
    notifyListeners();

    try {
      _apiClient = ApiClient(baseUrl: AppConstants.apiBaseUrl);

      final payload = <String, dynamic>{};
      if (_requestedRole != null) {
        payload['requested_role'] = _requestedRole!.name;
        _requestedRole = null;
      }

      final response = await _apiClient!.post('/api/v1/auth/register', payload);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _applyProfileData(data);

        if (_currentRole == UserRole.volunteer && _locationService != null) {
          try {
            final pos = await _locationService!.getCurrentPosition();
            await refreshHistoricalTasks(latitude: pos['lat'], longitude: pos['lon']);
          } catch (_) {
            await refreshHistoricalTasks();
          }
        } else {
          await refreshHistoricalTasks();
        }
      } else {
        _backendError = 'Permission denied or backend error. Code: ${response.statusCode}';
      }
    } catch (_) {
      _backendError = 'Could not connect to the SevaSetu secure server.';
    } finally {
      _isLoadingUser = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfileFromServer() async {
    if (_apiClient == null) return;
    try {
      final response = await _apiClient!.get('/api/v1/profile');
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _applyProfileData(data);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[AppState] refreshProfileFromServer failed: $e');
      }
    }
  }

  void setNavIndex(int index) {
    _currentNavIndex = index;
    notifyListeners();
  }

  Future<void> toggleLocationTracking() async {
    if (_locationService != null) {
      await _locationService!.toggleTracking();
      notifyListeners();
    }
  }

  Future<void> revokeLocation() async {
    if (_locationService != null && _locationService!.isTracking) {
      await _locationService!.toggleTracking();
    }
    try {
      await _apiClient?.delete('/api/v1/location/revoke');
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> submitSeverityFeedback({
    required String geohash,
    required String needType,
    required String feedback,
    String? note,
  }) async {
    if (_apiClient == null) return false;
    try {
      final response = await _apiClient!.post('/api/v1/severity/feedback', {
        'geohash': geohash,
        'need_type': needType,
        'feedback': feedback,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('[AppState] Severity feedback failed: $e');
      }
      return false;
    }
  }

  void addFieldReport(FieldReport report) {
    _reports.insert(0, report);
    notifyListeners();
  }

  void updateTaskStatus(String taskId, TaskStatus status) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        status: status,
        completedAt: status == TaskStatus.completed ? DateTime.now() : null,
      );
      notifyListeners();
    }
  }

  void acceptTask(String taskId, String volunteerId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        status: TaskStatus.assigned,
        assignedTo: volunteerId,
      );
      notifyListeners();
    }
  }

  Future<bool> submitReport({
    required String needType,
    required String urgency,
    required String description,
    List<String>? mediaUrls,
  }) async {
    if (_apiClient == null) return false;

    try {
      final pos = await _locationService!.getCurrentPosition();
      final payload = {
        'latitude': pos['lat'],
        'longitude': pos['lon'],
        'need_type': needType.toLowerCase(),
        'severity': urgency.toLowerCase(),
        'description': description,
        'media_urls': mediaUrls ?? [],
      };

      final response = await _apiClient!.post('/api/v1/reports', payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reportId = data['id'] ?? data['event_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        final report = FieldReport(
          id: reportId,
          ngoId: _currentUser?.ngoId ?? 'local',
          submittedBy: _currentUser?.id ?? 'me',
          needType: needType,
          description: description,
          location: '${pos['lat']?.toStringAsFixed(3)}, ${pos['lon']?.toStringAsFixed(3)}',
          latitude: pos['lat']!,
          longitude: pos['lon']!,
          urgency: urgency,
          estimatedPeopleAffected: 0,
          source: ReportSource.text,
          ward: 'unresolved',
        );
        addFieldReport(report);
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[AppState] Submit report failed: $e');
      }
      return false;
    }
  }

  UserRole get currentRole => _currentRole;
  AppUser? get currentUser => _currentUser;
  bool get isLoadingUser => _isLoadingUser;
  bool get isLoading => _isLoading;
  String? get backendError => _backendError;
  ApiClient? get apiClient => _apiClient;
  LocationService? get locationService => _locationService;
  bool get isAuthenticated => _currentUser != null;

  List<FieldReport> get reports => _reports;
  List<VolunteerTask> get tasks => _tasks;
  List<VolunteerTask> get openTasks =>
      _tasks.where((t) => t.status == TaskStatus.open).toList();
  List<VolunteerTask> get activeTasks => _tasks
      .where(
        (t) =>
            t.status == TaskStatus.assigned ||
            t.status == TaskStatus.inProgress,
      )
      .toList();
  List<VolunteerTask> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();
  List<AppUser> get volunteers => _volunteers;
  List<AppUser> get availableVolunteers =>
      _volunteers.where((v) => v.isAvailable).toList();
  List<CrisisAlert> get crisisAlerts => _crisisAlerts;
  List<CrisisAlert> get activeAlerts =>
      _crisisAlerts.where((a) => a.isActive).toList();
  Map<String, dynamic> get impactMetrics => _computeImpactMetrics();
  List<CrisisAlert> get derivedCrisisAlerts {
    final criticalTasks = _tasks.where(
      (t) => t.urgency == 'Critical' && t.status != TaskStatus.completed,
    );
    return criticalTasks
        .map(
          (t) => CrisisAlert(
            id: 'alert-${t.id}',
            prediction: 'Critical need detected: ${t.title}',
            affectedArea: t.ward.isNotEmpty ? t.ward : t.location,
            ward: t.ward,
            latitude: t.latitude,
            longitude: t.longitude,
            severity: AlertSeverity.critical,
            dataSource: 'Pipeline Analysis',
            predictedDate: t.createdAt,
            createdAt: t.createdAt,
          ),
        )
        .toList();
  }
  int get currentNavIndex => _currentNavIndex;
  int get reportCount => _reports.length;
  int get criticalTaskCount => _tasks
      .where((t) => t.urgency == 'Critical' && t.status != TaskStatus.completed)
      .length;
  int get totalPeopleAffected =>
      _reports.fold(0, (sum, r) => sum + r.estimatedPeopleAffected);

  Map<String, dynamic> _computeImpactMetrics() {
    final completed = completedTasks;
    final total = _tasks.length;
    final livesImproved = _tasks.fold<int>(0, (sum, t) => sum + t.estimatedPeopleAffected);
    final completionRate = total > 0 ? (completed.length / total * 100).round() : 0;

    final sdgCounts = <int, int>{};
    final sdgPeople = <int, int>{};
    for (final task in _tasks) {
      for (final tag in task.sdgTags) {
        sdgCounts[tag] = (sdgCounts[tag] ?? 0) + 1;
        sdgPeople[tag] = (sdgPeople[tag] ?? 0) + task.estimatedPeopleAffected;
      }
    }

    return {
      'livesImproved': livesImproved,
      'completedCount': completed.length,
      'totalCount': total,
      'completionRate': completionRate,
      'sdgCounts': sdgCounts,
      'sdgPeople': sdgPeople,
    };
  }
}