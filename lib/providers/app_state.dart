import 'package:flutter/material.dart';
import '../models/field_report_model.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../models/crisis_alert_model.dart';
import '../services/mock_data_service.dart';

class AppState extends ChangeNotifier {
  // Current user (simulated login)
  UserRole _currentRole = UserRole.coordinator;
  late AppUser _currentUser;

  // Data
  List<FieldReport> _reports = [];
  List<VolunteerTask> _tasks = [];
  List<AppUser> _volunteers = [];
  List<CrisisAlert> _crisisAlerts = [];
  Map<String, dynamic> _impactMetrics = {};

  // UI state
  int _currentNavIndex = 0;
  final bool _isLoading = false;

  AppState() {
    _loadData();
  }

  // Getters
  UserRole get currentRole => _currentRole;
  AppUser get currentUser => _currentUser;
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
  bool get isLoading => _isLoading;

  // Stats
  int get criticalTaskCount =>
      _tasks.where((t) => t.urgency == 'Critical' && t.status != TaskStatus.completed).length;
  int get totalPeopleAffected =>
      _reports.fold(0, (sum, r) => sum + r.estimatedPeopleAffected);

  void _loadData() {
    _reports = MockDataService.getFieldReports();
    _tasks = MockDataService.getTasks();
    _volunteers = MockDataService.getVolunteers();
    _crisisAlerts = MockDataService.getCrisisAlerts();
    _impactMetrics = MockDataService.getImpactMetrics();
    _currentUser = AppUser(
      id: 'coord-001',
      name: 'Arjun Kapoor',
      email: 'arjun@sevasetu.org',
      role: UserRole.coordinator,
      location: 'Mumbai',
      latitude: 19.0760,
      longitude: 72.8777,
    );
    notifyListeners();
  }

  void switchRole(UserRole role) {
    _currentRole = role;
    switch (role) {
      case UserRole.coordinator:
        _currentUser = AppUser(
          id: 'coord-001',
          name: 'Arjun Kapoor',
          email: 'arjun@sevasetu.org',
          role: UserRole.coordinator,
          location: 'Mumbai',
        );
      case UserRole.volunteer:
        _currentUser = _volunteers.first;
      case UserRole.ngoWorker:
        _currentUser = AppUser(
          id: 'ngo-worker-001',
          name: 'Priya Sharma',
          email: 'priya@goonj.org',
          role: UserRole.ngoWorker,
          ngoId: 'ngo-goonj',
          location: 'Mumbai',
        );
    }
    _currentNavIndex = 0;
    notifyListeners();
  }

  void setNavIndex(int index) {
    _currentNavIndex = index;
    notifyListeners();
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
