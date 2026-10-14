import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, [this.statusCode = 0]);

  @override
  String toString() => message;
}

/// Unified API client that automatically manages base URL, Bearer auth headers,
/// timeouts, and error extraction.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final http.Client _client = http.Client();
  final Duration _timeout = const Duration(seconds: 10);

  Future<Map<String, String>> _getHeaders({Map<String, String>? extraHeaders}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('splitup_auth_token');
      final userId = prefs.getString('splitup_user_id');

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
      } else if (userId != null && userId.isNotEmpty) {
        headers['Authorization'] = 'Bearer user:$userId';
        headers['x-user-id'] = userId;
      }
    } catch (_) {}

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  String _extractErrorMessage(String responseBody, int statusCode) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('error') && decoded['error'] is Map) {
          final errMap = decoded['error'] as Map;
          if (errMap.containsKey('message')) return errMap['message'].toString();
        }
        if (decoded.containsKey('message')) return decoded['message'].toString();
      }
    } catch (_) {}
    return 'Server error (status $statusCode)';
  }

  Future<dynamic> get(String endpoint) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await _client.get(uri, headers: headers).timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw ApiException(_extractErrorMessage(response.body, response.statusCode), response.statusCode);
  }

  Future<dynamic> post(String endpoint, [Map<String, dynamic>? body]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await _client
        .post(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw ApiException(_extractErrorMessage(response.body, response.statusCode), response.statusCode);
  }

  Future<dynamic> patch(String endpoint, [Map<String, dynamic>? body]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await _client
        .patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw ApiException(_extractErrorMessage(response.body, response.statusCode), response.statusCode);
  }

  Future<dynamic> delete(String endpoint, [Map<String, dynamic>? body]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await _client
        .delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw ApiException(_extractErrorMessage(response.body, response.statusCode), response.statusCode);
  }
}
