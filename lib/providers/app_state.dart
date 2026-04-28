import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/field_report_model.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../models/crisis_alert_model.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';

class AppState extends ChangeNotifier {
  // Current user
  ApiClient? _apiClient;
  LocationService? _locationService;
  UserRole _currentRole = UserRole.volunteer;
  AppUser? _currentUser;
  bool _isLoadingUser = false;
  final bool _isLoading = false;
  String? _backendError;

  // Data
  final List<FieldReport> _reports = [];
  final List<VolunteerTask> _tasks = [];
  final List<AppUser> _volunteers = [];
  final List<CrisisAlert> _crisisAlerts = [];

  // UI state
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
    } else if (!isVolunteer) {
      // Coordinators and NGO workers can inspect global context without a shared location.
    } else {
      return;
    }

    try {
      final uri = Uri.parse(
        'http://127.0.0.1:8000/api/v1/tasks',
      ).replace(queryParameters: queryParams);
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
      if (kDebugMode) print('[AppState] refreshHistoricalTasks failed: $e');
    }
  }

  void setRequestedRole(UserRole role) {
    _requestedRole = role;
  }

  // Getters
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
  int get currentNavIndex => _currentNavIndex;
  int get reportCount => _reports.length;

  /// Computed SDG impact metrics from real task data
  Map<String, dynamic> _computeImpactMetrics() {
    final completed = completedTasks;
    final total = _tasks.length;
    final livesImproved = _tasks.fold<int>(0, (sum, t) => sum + t.estimatedPeopleAffected);
    final completionRate = total > 0 ? (completed.length / total * 100).round() : 0;

    // Group by SDG tags
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

  /// Generates synthetic crisis alerts from high-urgency open tasks
  List<CrisisAlert> get derivedCrisisAlerts {
    final criticalTasks = _tasks.where(
      (t) => t.urgency == 'Critical' && t.status != TaskStatus.completed,
    );
    return criticalTasks.map((t) => CrisisAlert(
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
    )).toList();
  }

  // Stats
  int get criticalTaskCount => _tasks
      .where((t) => t.urgency == 'Critical' && t.status != TaskStatus.completed)
      .length;
  int get totalPeopleAffected =>
      _reports.fold(0, (sum, r) => sum + r.estimatedPeopleAffected);

  // Initialize actual user from Firebase and Backend
  Future<void> initializeUser(User firebaseUser) async {
    // 12-Hour Session Security Limit
    final lastSignIn = firebaseUser.metadata.lastSignInTime;
    if (lastSignIn != null) {
      if (DateTime.now().difference(lastSignIn).inHours >= 12) {
        // Enforce strict re-authentication
        await FirebaseAuth.instance.signOut();
        return;
      }
    }

    _isLoadingUser = true;
    _backendError = null;
    notifyListeners();

    try {
      _apiClient = ApiClient(baseUrl: "http://127.0.0.1:8000");

      // Pass the requested role if the user just signed up
      final payload = <String, dynamic>{};
      if (_requestedRole != null) {
        payload['requested_role'] = _requestedRole!.name;
        _requestedRole = null; // Consume the requested role
      }

      // Calls FastApi to verify token and return profile
      final response = await _apiClient!.post("/api/v1/auth/register", payload);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Map backend role enum to local Flutter enum
        UserRole mappedRole = UserRole.volunteer;
        if (data['role'] == 'coordinator') mappedRole = UserRole.coordinator;
        if (data['role'] == 'ngo_worker') mappedRole = UserRole.ngoWorker;

        _currentRole = mappedRole;
        _currentUser = AppUser(
          id: data['uid'] ?? firebaseUser.uid,
          name: data['name'] ?? firebaseUser.displayName ?? 'User',
          email: data['email'] ?? firebaseUser.email ?? '',
          role: mappedRole,
          ngoId: data['organization_id'],
          phone: data['phone'],
          skills: _parseSkills(data['skills']),
          location: data['location'],
          isAvailable: data['is_available'] ?? true,
          createdAt: _parseBackendDate(data['created_at']),
        );
        if (mappedRole == UserRole.volunteer && _locationService != null) {
          try {
            final pos = await _locationService!.getCurrentPosition();
            await refreshHistoricalTasks(
              latitude: pos['lat'],
              longitude: pos['lon'],
            );
          } catch (_) {
            await refreshHistoricalTasks();
          }
        } else {
          await refreshHistoricalTasks();
        }
      } else {
        _backendError =
            "Permission denied or backend error. Code: ${response.statusCode}";
      }
    } catch (e) {
      _backendError = "Could not connect to the SevaSetu secure server.";
    } finally {
      _isLoadingUser = false;
      notifyListeners();
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

  /// Revoke location data from the backend (right to be forgotten)
  Future<void> revokeLocation() async {
    if (_locationService != null && _locationService!.isTracking) {
      await _locationService!.toggleTracking(); // stop tracking first
    }
    try {
      await _apiClient?.delete('/api/v1/location/revoke');
    } catch (_) {}
    notifyListeners();
  }

  /// Submit severity feedback for a community need (coordinator only)
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
      if (kDebugMode) print('[AppState] Severity feedback failed: $e');
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
      // 1. Get current location
      final pos = await _locationService!.getCurrentPosition();

      // 2. Prepare payload
      final payload = {
        "latitude": pos['lat'],
        "longitude": pos['lon'],
        "need_type": needType.toLowerCase(),
        "severity": urgency.toLowerCase(),
        "description": description,
        "media_urls": mediaUrls ?? [],
      };

      // 3. Send to backend
      final response = await _apiClient!.post("/api/v1/reports", payload);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 4. Update local state
        final data = jsonDecode(response.body);
        final report = FieldReport(
          id: data['id'],
          ngoId: _currentUser?.ngoId ?? 'local',
          submittedBy: _currentUser?.id ?? 'me',
          needType: needType,
          description: description,
          location:
              "${pos['lat']?.toStringAsFixed(3)}, ${pos['lon']?.toStringAsFixed(3)}",
          latitude: pos['lat']!,
          longitude: pos['lon']!,
          urgency: urgency,
          estimatedPeopleAffected: 0, // Backend might calculate this later
          source: ReportSource.text, // Default
          ward: 'unresolved',
        );
        addFieldReport(report);
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('[AppState] Submit report failed: $e');
      return false;
    }
  }
}
