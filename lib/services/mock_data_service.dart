import '../models/field_report_model.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import '../models/crisis_alert_model.dart';

/// MockDataService — provides realistic sample data for the MVP prototype.
/// This will be replaced with Firebase in production.
class MockDataService {
  static List<FieldReport> getFieldReports() => [
        FieldReport(
          id: 'fr-001',
          ngoId: 'ngo-goonj',
          submittedBy: 'Priya Sharma',
          needType: 'Food & Nutrition',
          description:
              'Ward 14 Slum Area — 200+ families facing food shortage due to recent flooding. '
              'Three community kitchens have shut down. Urgent need for dry ration kits.',
          location: 'Dharavi, Ward 14, Mumbai',
          latitude: 19.0430,
          longitude: 72.8567,
          urgency: 'Critical',
          estimatedPeopleAffected: 850,
          source: ReportSource.camera,
          ward: 'Ward 14',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        FieldReport(
          id: 'fr-002',
          ngoId: 'ngo-cry',
          submittedBy: 'Rahul Verma',
          needType: 'Medical Assistance',
          description:
              'Waterborne disease outbreak in Govandi area. 50+ children showing symptoms '
              'of diarrhea and dehydration. Need medical volunteers with ORS supplies.',
          location: 'Govandi, Ward 23, Mumbai',
          latitude: 19.0553,
          longitude: 72.9197,
          urgency: 'Critical',
          estimatedPeopleAffected: 320,
          source: ReportSource.text,
          ward: 'Ward 23',
          timestamp: DateTime.now().subtract(const Duration(hours: 6)),
        ),
        FieldReport(
          id: 'fr-003',
          ngoId: 'ngo-pratham',
          submittedBy: 'Anita Desai',
          needType: 'Education Support',
          description:
              'Community school in Bandra East lost teaching materials in rain. '
              '120 children need notebooks, textbooks, and a temporary teaching setup.',
          location: 'Bandra East, Ward 9, Mumbai',
          latitude: 19.0596,
          longitude: 72.8437,
          urgency: 'Medium',
          estimatedPeopleAffected: 120,
          source: ReportSource.voice,
          ward: 'Ward 9',
          timestamp: DateTime.now().subtract(const Duration(hours: 12)),
        ),
        FieldReport(
          id: 'fr-004',
          ngoId: 'ngo-goonj',
          submittedBy: 'Vikram Patil',
          needType: 'Shelter & Housing',
          description:
              'Temporary shelters in Kurla damaged by storm. 45 families are without cover. '
              'Need tarpaulins, volunteers for repair, and building materials.',
          location: 'Kurla West, Ward 17, Mumbai',
          latitude: 19.0728,
          longitude: 72.8790,
          urgency: 'High',
          estimatedPeopleAffected: 180,
          source: ReportSource.whatsapp,
          ward: 'Ward 17',
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
        ),
        FieldReport(
          id: 'fr-005',
          ngoId: 'ngo-cry',
          submittedBy: 'Meera Iyer',
          needType: 'Clean Water',
          description:
              'Water supply contaminated in Mankhurd. Community hand pump broken for 5 days. '
              '300 residents relying on tanker water. Need repair volunteers and water purification tablets.',
          location: 'Mankhurd, Ward 25, Mumbai',
          latitude: 19.0630,
          longitude: 72.9320,
          urgency: 'High',
          estimatedPeopleAffected: 300,
          source: ReportSource.text,
          ward: 'Ward 25',
          timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
        ),
        FieldReport(
          id: 'fr-006',
          ngoId: 'ngo-pratham',
          submittedBy: 'Sanjay Kumar',
          needType: 'Child Welfare',
          description:
              '15 street children near Dadar station without any adult supervision. '
              'Need volunteers for child safety assessment and temporary care coordination.',
          location: 'Dadar, Ward 11, Mumbai',
          latitude: 19.0176,
          longitude: 72.8441,
          urgency: 'Medium',
          estimatedPeopleAffected: 15,
          source: ReportSource.camera,
          ward: 'Ward 11',
          timestamp: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];

  static List<VolunteerTask> getTasks() => [
        VolunteerTask(
          id: 'task-001',
          title: 'Distribute Dry Ration Kits',
          description:
              'Distribute 200 dry ration kits to families in Dharavi Ward 14. '
              'Coordinate with local community leaders for safe distribution points.',
          needType: 'Food & Nutrition',
          location: 'Dharavi, Ward 14, Mumbai',
          latitude: 19.0430,
          longitude: 72.8567,
          ward: 'Ward 14',
          urgency: 'Critical',
          requiredSkills: ['Logistics & Transportation', 'Food & Cooking'],
          estimatedPeopleAffected: 850,
          status: TaskStatus.open,
          sdgTags: [2],
          createdFromReportId: 'fr-001',
          ngoId: 'ngo-goonj',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        VolunteerTask(
          id: 'task-002',
          title: 'Medical Camp — Govandi Ward 23',
          description:
              'Set up emergency medical camp for waterborne disease outbreak. '
              'Administer ORS, check for dehydration in children, refer severe cases.',
          needType: 'Medical Assistance',
          location: 'Govandi, Ward 23, Mumbai',
          latitude: 19.0553,
          longitude: 72.9197,
          ward: 'Ward 23',
          urgency: 'Critical',
          requiredSkills: ['Medical & First Aid'],
          estimatedPeopleAffected: 320,
          status: TaskStatus.assigned,
          assignedTo: 'vol-001',
          sdgTags: [3],
          createdFromReportId: 'fr-002',
          ngoId: 'ngo-cry',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        VolunteerTask(
          id: 'task-003',
          title: 'Teaching Materials Distribution',
          description:
              'Collect and distribute notebooks, textbooks to Bandra East community school. '
              'Help set up temporary classroom with tarpaulin and chairs.',
          needType: 'Education Support',
          location: 'Bandra East, Ward 9, Mumbai',
          latitude: 19.0596,
          longitude: 72.8437,
          ward: 'Ward 9',
          urgency: 'Medium',
          requiredSkills: ['Teaching & Education', 'Administration'],
          estimatedPeopleAffected: 120,
          status: TaskStatus.completed,
          assignedTo: 'vol-003',
          sdgTags: [4],
          createdFromReportId: 'fr-003',
          ngoId: 'ngo-pratham',
          createdAt: DateTime.now().subtract(const Duration(hours: 10)),
          completedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        VolunteerTask(
          id: 'task-004',
          title: 'Shelter Repair — Kurla West',
          description:
              'Repair damaged temporary shelters for 45 families. '
              'Need volunteers with construction skills. Tarpaulins and tools provided.',
          needType: 'Shelter & Housing',
          location: 'Kurla West, Ward 17, Mumbai',
          latitude: 19.0728,
          longitude: 72.8790,
          ward: 'Ward 17',
          urgency: 'High',
          requiredSkills: ['Construction & Repair', 'Logistics & Transportation'],
          estimatedPeopleAffected: 180,
          status: TaskStatus.inProgress,
          assignedTo: 'vol-002',
          sdgTags: [11],
          createdFromReportId: 'fr-004',
          ngoId: 'ngo-goonj',
          createdAt: DateTime.now().subtract(const Duration(hours: 20)),
        ),
        VolunteerTask(
          id: 'task-005',
          title: 'Water Pump Repair & Purification',
          description:
              'Repair broken hand pump in Mankhurd. Distribute water purification tablets '
              'to 300+ residents while pump is being fixed.',
          needType: 'Clean Water',
          location: 'Mankhurd, Ward 25, Mumbai',
          latitude: 19.0630,
          longitude: 72.9320,
          ward: 'Ward 25',
          urgency: 'High',
          requiredSkills: ['Construction & Repair'],
          estimatedPeopleAffected: 300,
          status: TaskStatus.open,
          sdgTags: [6],
          createdFromReportId: 'fr-005',
          ngoId: 'ngo-cry',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

  static List<AppUser> getVolunteers() => [
        AppUser(
          id: 'vol-001',
          name: 'Dr. Amit Mehta',
          email: 'amit.mehta@email.com',
          role: UserRole.volunteer,
          skills: ['Medical & First Aid', 'Counseling & Support'],
          location: 'Andheri West, Mumbai',
          latitude: 19.1360,
          longitude: 72.8296,
          trustScore: 9.2,
          tasksCompleted: 34,
          totalHoursVolunteered: 156,
          isAvailable: true,
        ),
        AppUser(
          id: 'vol-002',
          name: 'Rakesh Sharma',
          email: 'rakesh.s@email.com',
          role: UserRole.volunteer,
          skills: [
            'Construction & Repair',
            'Logistics & Transportation',
            'Disaster Relief'
          ],
          location: 'Dadar, Mumbai',
          latitude: 19.0176,
          longitude: 72.8441,
          trustScore: 8.7,
          tasksCompleted: 28,
          totalHoursVolunteered: 112,
          isAvailable: true,
        ),
        AppUser(
          id: 'vol-003',
          name: 'Sneha Kulkarni',
          email: 'sneha.k@email.com',
          role: UserRole.volunteer,
          skills: ['Teaching & Education', 'Child Care', 'Administration'],
          location: 'Bandra, Mumbai',
          latitude: 19.0596,
          longitude: 72.8295,
          trustScore: 9.5,
          tasksCompleted: 42,
          totalHoursVolunteered: 205,
          isAvailable: false,
        ),
        AppUser(
          id: 'vol-004',
          name: 'Mohammed Farhan',
          email: 'farhan.m@email.com',
          role: UserRole.volunteer,
          skills: ['Food & Cooking', 'Logistics & Transportation'],
          location: 'Kurla, Mumbai',
          latitude: 19.0728,
          longitude: 72.8790,
          trustScore: 7.8,
          tasksCompleted: 15,
          totalHoursVolunteered: 67,
          isAvailable: true,
        ),
        AppUser(
          id: 'vol-005',
          name: 'Kavita Nair',
          email: 'kavita.n@email.com',
          role: UserRole.volunteer,
          skills: ['Counseling & Support', 'Child Care', 'Medical & First Aid'],
          location: 'Powai, Mumbai',
          latitude: 19.1162,
          longitude: 72.9047,
          trustScore: 8.9,
          tasksCompleted: 22,
          totalHoursVolunteered: 98,
          isAvailable: true,
        ),
      ];

  static List<CrisisAlert> getCrisisAlerts() => [
        CrisisAlert(
          id: 'alert-001',
          prediction:
              'Heavy rainfall predicted for South Mumbai. Historical data shows '
              '3x spike in food and shelter needs in low-lying wards within 48 hours of heavy rain.',
          affectedArea: 'Dharavi, Sion, Kurla',
          ward: 'Wards 14, 15, 17',
          latitude: 19.0430,
          longitude: 72.8567,
          severity: AlertSeverity.critical,
          dataSource: 'IMD Weather API + Historical Reports',
          preMobilizationTaskIds: ['task-001'],
          weatherData: 'IMD forecast: Very heavy rain (>150mm) expected 25-26 March.',
          predictedDate: DateTime.now().add(const Duration(days: 2)),
        ),
        CrisisAlert(
          id: 'alert-002',
          prediction:
              'Festival season combined with unsanitary conditions in Ward 23. '
              'Predict 2x increase in waterborne diseases based on previous year data.',
          affectedArea: 'Govandi, Mankhurd',
          ward: 'Wards 23, 25',
          latitude: 19.0553,
          longitude: 72.9197,
          severity: AlertSeverity.high,
          dataSource: 'Historical Reports + Festival Calendar',
          weatherData: 'Temperature: 34°C, Humidity: 85%',
          predictedDate: DateTime.now().add(const Duration(days: 7)),
        ),
        CrisisAlert(
          id: 'alert-003',
          prediction:
              'Rising temperatures and prolonged dry spell expected to cause water scarcity '
              'in Mankhurd and surrounding wards. Historical data shows water complaints double.',
          affectedArea: 'Mankhurd, Chembur',
          ward: 'Wards 25, 26',
          latitude: 19.0630,
          longitude: 72.9320,
          severity: AlertSeverity.moderate,
          dataSource: 'IMD Weather API + Water Supply Records',
          weatherData: 'No rain forecast for next 14 days. Max temp: 37°C.',
          predictedDate: DateTime.now().add(const Duration(days: 14)),
        ),
      ];

  // Impact metrics
  static Map<String, dynamic> getImpactMetrics() => {
        'totalVolunteerHours': 638,
        'totalTasksCompleted': 141,
        'totalPeopleServed': 12450,
        'activeVolunteers': 87,
        'activeNGOs': 5,
        'sdgBreakdown': {
          'SDG 2 - Zero Hunger': {'hours': 185, 'tasks': 42, 'people': 4200},
          'SDG 3 - Good Health': {'hours': 156, 'tasks': 34, 'people': 3200},
          'SDG 4 - Quality Education': {
            'hours': 102,
            'tasks': 25,
            'people': 1800
          },
          'SDG 6 - Clean Water': {'hours': 89, 'tasks': 18, 'people': 1500},
          'SDG 11 - Sustainable Cities': {
            'hours': 67,
            'tasks': 15,
            'people': 1200
          },
          'SDG 1 - No Poverty': {'hours': 39, 'tasks': 7, 'people': 550},
        },
        'wardImpact': {
          'Ward 14': {
            'reportsBefore': 45,
            'reportsAfter': 18,
            'reduction': 60
          },
          'Ward 23': {
            'reportsBefore': 38,
            'reportsAfter': 22,
            'reduction': 42
          },
          'Ward 9': {
            'reportsBefore': 25,
            'reportsAfter': 12,
            'reduction': 52
          },
          'Ward 17': {
            'reportsBefore': 30,
            'reportsAfter': 19,
            'reduction': 37
          },
          'Ward 25': {
            'reportsBefore': 42,
            'reportsAfter': 28,
            'reduction': 33
          },
        },
        'weeklyTrend': [12, 18, 24, 22, 31, 28, 35],
      };
}
