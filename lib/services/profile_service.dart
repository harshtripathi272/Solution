import '../models/user_model.dart';
import 'api_client.dart';

class ProfileService {
  static ApiClient _getApiClient() {
    return ApiClient(baseUrl: "http://127.0.0.1:8000");
  }

  /// Update volunteer profile (name, phone, skills, location, availability)
  static Future<void> updateVolunteerProfile(String uid, AppUser user) async {
    try {
      final apiClient = _getApiClient();
      final response = await apiClient.put(
        "/api/v1/profile/update",
        {
          'name': user.name,
          'phone': user.phone ?? '',
          'skills': user.skills,
          'location': user.location ?? '',
          'is_available': user.isAvailable,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Backend update failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to update volunteer profile: $e');
    }
  }

  /// Update NGO worker profile (name, phone, organization, location)
  static Future<void> updateNGOWorkerProfile(String uid, AppUser user) async {
    try {
      final apiClient = _getApiClient();
      final response = await apiClient.put(
        "/api/v1/profile/update",
        {
          'name': user.name,
          'phone': user.phone ?? '',
          'organization_id': user.ngoId ?? '',
          'location': user.location ?? '',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Backend update failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to update NGO worker profile: $e');
    }
  }

  /// Update coordinator profile (name, phone, location)
  static Future<void> updateCoordinatorProfile(String uid, AppUser user) async {
    try {
      final apiClient = _getApiClient();
      final response = await apiClient.put(
        "/api/v1/profile/update",
        {
          'name': user.name,
          'phone': user.phone ?? '',
          'location': user.location ?? '',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Backend update failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to update coordinator profile: $e');
    }
  }
}

