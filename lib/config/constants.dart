import 'package:flutter/foundation.dart';

class AppConstants {
  static const String appName = 'SevaSetu';
  static const String appTagline = 'Bridging Service, Building Impact';
  static const String appVersion = '1.0.0';

  // Backend API configuration
  static String get apiBaseUrl {
    const overrideUrl = String.fromEnvironment('API_BASE_URL');
    if (overrideUrl.isNotEmpty) {
      return overrideUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://localhost:8000';
    }
  }

  static const String heatmapDataEndpoint = '/api/v1/heatmap-data';

  // SDG Goals relevant to this app
  static const Map<int, String> sdgGoals = {
    1: 'No Poverty',
    2: 'Zero Hunger',
    3: 'Good Health & Well-being',
    4: 'Quality Education',
    5: 'Gender Equality',
    6: 'Clean Water & Sanitation',
    8: 'Decent Work & Economic Growth',
    10: 'Reduced Inequalities',
    11: 'Sustainable Cities',
    13: 'Climate Action',
    16: 'Peace, Justice & Strong Institutions',
  };

  // Task urgency levels
  static const List<String> urgencyLevels = [
    'Critical',
    'High',
    'Medium',
    'Low',
  ];

  // Volunteer skill categories
  static const List<String> skillCategories = [
    'Medical & First Aid',
    'Teaching & Education',
    'Food & Cooking',
    'Logistics & Transportation',
    'Construction & Repair',
    'Counseling & Support',
    'Technology & IT',
    'Administration',
    'Disaster Relief',
    'Child Care',
    'Environment & Cleanup',
    'Other',
  ];

  // Need types for field reports
  static const List<String> needTypes = [
    'Food & Nutrition',
    'Medical Assistance',
    'Shelter & Housing',
    'Education Support',
    'Clean Water',
    'Sanitation',
    'Clothing',
    'Disaster Relief',
    'Child Welfare',
    'Elder Care',
    'Women Safety',
    'Environmental',
    'Other',
  ];
}
