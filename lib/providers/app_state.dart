import 'dart:convert';
import 'package:flutter/material.dart';
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
  List<FieldReport> _reports = [];
  List<VolunteerTask> _tasks = [];
  List<AppUser> _volunteers = [];
  List<CrisisAlert> _crisisAlerts = [];
  Map<String, dynamic> _impactMetrics = {};

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
  List<VolunteerTask> get activeTasks =>
      _tasks.where((t) => t.status == TaskStatus.assigned || t.status == TaskStatus.inProgress).toList();
  List<VolunteerTask> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();
  List<AppUser> get volunteers => _volunteers;
  List<AppUser> get availableVolunteers =>
      _volunteers.where((v) => v.isAvailable).toList();
  List<CrisisAlert> get crisisAlerts => _crisisAlerts;
  List<CrisisAlert> get activeAlerts =>
      _crisisAlerts.where((a) => a.isActive).toList();
  Map<String, dynamic> get impactMetrics => _impactMetrics;
  int get currentNavIndex => _currentNavIndex;

  // Stats
  int get criticalTaskCount =>
      _tasks.where((t) => t.urgency == 'Critical' && t.status != TaskStatus.completed).length;
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
      } else {
        _backendError = "Permission denied or backend error. Code: ${response.statusCode}";
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
}
