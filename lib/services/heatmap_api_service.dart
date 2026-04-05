import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:hive/hive.dart';
import '../models/heatmap_point.dart';
import '../config/constants.dart';

class HeatmapApiService {
  static const String _cacheBoxName = 'heatmap_cache';
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  static final HeatmapApiService _instance = HeatmapApiService._internal();

  HeatmapApiService._internal();

  factory HeatmapApiService() {
    return _instance;
  }

  /// Gets Firebase Auth token for API requests
  Future<String?> _getToken() async {
    final user = firebase.FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken();
    }
    return null;
  }

  /// Builds request headers with auth token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetches aggregated heatmap data from backend API
  /// 
  /// Parameters:
  /// - [region]: Filter by region (e.g., "bihar", "assam")
  /// - [needType]: Filter by need type (e.g., "water_sanitation", "medical")
  /// - [minSeverity]: Minimum severity threshold (0.0–1.0)
  /// - [timeRange]: Time range for data (e.g., "30d", "90d")
  /// 
  /// Returns list of HeatmapPoint objects, or cached data if fresh
  /// Throws HeatmapException on critical failures
  Future<List<HeatmapPoint>> fetchHeatmapData({
    String? region,
    String? needType,
    double minSeverity = 0.1,
    String timeRange = '30d',
  }) async {
    try {
      // Check cache first
      final cachedData = await _getFromCache(region, needType, minSeverity, timeRange);
      if (cachedData != null) {
        return cachedData;
      }

      // Build query parameters
      final queryParams = <String, String>{
        'min_severity': minSeverity.toString(),
        'time_range': timeRange,
        if (region != null && region.isNotEmpty) 'region': region,
        if (needType != null && needType.isNotEmpty) 'need_type': needType,
      };

      final uri = Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.heatmapDataEndpoint}')
          .replace(queryParameters: queryParams);

      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw HeatmapException(
              'Request timeout. Please try again.',
              messageHi: 'अनुरोध समय सीमा समाप्त। कृपया पुनः प्रयास करें।',
            ),
          );

      if (response.statusCode == 200) {
        // Parse GeoJSON response
        final geoJson = jsonDecode(response.body) as Map<String, dynamic>;
        final features = (geoJson['features'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        
        final points = features
            .map((feature) => HeatmapPoint.fromJson(feature))
            .toList();

        // Cache the response
        await _saveToCache(region, needType, minSeverity, timeRange, points);

        return points;
      } else if (response.statusCode == 401) {
        throw HeatmapException(
          'Unauthorized. Please log in again.',
          messageHi: 'अनुमति नहीं है। कृपया फिर से लॉगिन करें।',
        );
      } else if (response.statusCode == 403) {
        throw HeatmapException(
          'You do not have permission to view this data.',
          messageHi: 'आपको इस डेटा को देखने की अनुमति नहीं है।',
        );
      } else {
        throw HeatmapException(
          'Server error: ${response.statusCode}. Please try again later.',
          messageHi: 'सर्वर त्रुटि। कृपया बाद में पुनः प्रयास करें।',
        );
      }
    } on http.ClientException catch (e) {
      // Network error - try to return cached data
      final cachedData = await _getFromCache(region, needType, minSeverity, timeRange);
      if (cachedData != null) {
        return cachedData;
      }
      throw HeatmapException(
        'Network error: ${e.message}. Check your internet connection.',
        messageHi: 'नेटवर्क त्रुटि। अपनी इंटरनेट कनेक्शन जांचें।',
      );
    } on HeatmapException {
      rethrow;
    } catch (e) {
      throw HeatmapException(
        'Unexpected error: $e',
        messageHi: 'अप्रत्याशित त्रुटि। कृपया सहायता से संपर्क करें।',
      );
    }
  }

  /// Saves data to Hive cache with timestamp
  Future<void> _saveToCache(
    String? region,
    String? needType,
    double minSeverity,
    String timeRange,
    List<HeatmapPoint> data,
  ) async {
    try {
      final box = await Hive.openBox<String>(_cacheBoxName);
      final key = _buildCacheKey(region, needType, minSeverity, timeRange);
      
      final cacheData = {
        'data': data.map((p) => {
          'latitude': p.latitude,
          'longitude': p.longitude,
          'severity': p.severity,
          'need_type': p.needType,
          'population_affected': p.populationAffected,
          'confidence': p.confidence,
          'timestamp': p.timestamp.toIso8601String(),
          'geohash': p.geohash,
          'need_type_breakdown': p.needTypeBreakdown,
          'source_count': p.sourceCount,
        }).toList(),
        'cached_at': DateTime.now().toIso8601String(),
      };
      
      await box.put(key, jsonEncode(cacheData));
    } catch (e) {
      // Silently fail cache write; don't break the flow
      debugPrint('Cache write failed: $e');
    }
  }

  /// Retrieves cached data if fresh (within 5 minutes)
  Future<List<HeatmapPoint>?> _getFromCache(
    String? region,
    String? needType,
    double minSeverity,
    String timeRange,
  ) async {
    try {
      final box = await Hive.openBox<String>(_cacheBoxName);
      final key = _buildCacheKey(region, needType, minSeverity, timeRange);
      
      final cachedJson = box.get(key);
      if (cachedJson == null) return null;

      final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(cacheData['cached_at'] as String);
      
      // Check if cache is still fresh
      if (cachedAt != null && DateTime.now().difference(cachedAt) < _cacheDuration) {
        final dataList = (cacheData['data'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>()
            .map((item) => HeatmapPoint(
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
              severity: (item['severity'] as num).toDouble(),
              needType: item['need_type'] as String,
              populationAffected: item['population_affected'] as int,
              confidence: (item['confidence'] as num).toDouble(),
              timestamp: DateTime.parse(item['timestamp'] as String),
              geohash: item['geohash'] as String,
              needTypeBreakdown: Map<String, int>.from(
                (item['need_type_breakdown'] as Map<dynamic, dynamic>?)?.cast<String, int>() ?? {},
              ),
              sourceCount: item['source_count'] as int,
            ))
            .toList();
        
        return dataList ?? [];
      }
      
      // Cache expired, remove it
      await box.delete(key);
      return null;
    } catch (e) {
      // Silently fail cache read; return null to proceed with API call
      debugPrint('Cache read failed: $e');
      return null;
    }
  }

  /// Clears all cached heatmap data
  Future<void> clearCache() async {
    try {
      final box = await Hive.openBox<String>(_cacheBoxName);
      await box.clear();
    } catch (e) {
      debugPrint('Failed to clear cache: $e');
    }
  }

  /// Builds a cache key from filter parameters
  String _buildCacheKey(
    String? region,
    String? needType,
    double minSeverity,
    String timeRange,
  ) {
    return '${region ?? 'all'}_${needType ?? 'all'}_${minSeverity}_$timeRange';
  }

  /// Sets a custom base URL (useful for different environments)
  static void setBaseUrl(String newBaseUrl) {
    // To implement: make baseUrl non-final if needed for testing
    // For now, modify _baseUrl constant directly
  }
}
