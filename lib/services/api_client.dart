import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiClient {
  final String baseUrl;

  ApiClient({required this.baseUrl});

  Future<String?> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken(forceRefresh);
    }
    return null;
  }

  Future<Map<String, String>> _getHeaders({bool forceRefresh = false}) async {
    final token = await _getToken(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('Not authenticated: no Firebase ID token available');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    return await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }
}

