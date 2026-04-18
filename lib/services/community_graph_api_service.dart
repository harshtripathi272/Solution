import 'dart:convert';

import '../config/constants.dart';
import '../models/community_graph_models.dart';
import 'api_client.dart';

class CommunityGraphApiService {
  final ApiClient _client;

  CommunityGraphApiService({ApiClient? client}) : _client = client ?? ApiClient(baseUrl: AppConstants.apiBaseUrl);

  Future<CommunityGraphOverview> fetchOverview({int limit = 12}) async {
    final response = await _client.get('/api/v1/community-graph/overview?limit=$limit');
    if (response.statusCode != 200) {
      throw Exception('Failed to load community graph overview: ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CommunityGraphOverview.fromMap(payload);
  }

  Future<CommunityProfile> fetchProfile(String communityId) async {
    final response = await _client.get('/api/v1/community-graph/$communityId');
    if (response.statusCode != 200) {
      throw Exception('Failed to load community graph profile: ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CommunityProfile.fromMap(payload);
  }
}
