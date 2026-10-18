import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? errorData;
  const ApiException(this.message, [this.statusCode = 0, this.errorData]);

  @override
  String toString() => message;
}

/// Unified API client that automatically manages base URL, Bearer auth headers,
/// idempotency keys, timeouts, and error extraction.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final http.Client _client = http.Client();
  http.Client? _mockClient;

  static void setMockClient(http.Client? client) {
    _instance._mockClient = client;
  }

  http.Client get _activeClient => _mockClient ?? _client;
  final Duration _timeout = const Duration(seconds: 12);

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
      }
    } catch (_) {}

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  String _generateIdempotencyKey() {
    final rand = math.Random().nextInt(1000000).toString().padLeft(6, '0');
    return 'idemp_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  String _extractErrorMessage(String responseBody, int statusCode, {String? fallback}) {
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
    return fallback ?? 'Server error (status $statusCode)';
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    Map<String, dynamic>? errorData;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        errorData = decoded;
      }
    } catch (_) {}

    if (response.statusCode == 401) {
      // Clear cached auth token on 401 to prevent stale unauthorized loops
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('splitup_auth_token');
      }).catchError((_) {});

      throw ApiException(
        _extractErrorMessage(
          response.body,
          response.statusCode,
          fallback: 'Session expired or unauthorized. Please log in again.',
        ),
        401,
        errorData,
      );
    }

    throw ApiException(
      _extractErrorMessage(response.body, response.statusCode),
      response.statusCode,
      errorData,
    );
  }

  Future<dynamic> get(String endpoint, {Map<String, String>? headers}) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final reqHeaders = await _getHeaders(extraHeaders: headers);

    try {
      final response = await _activeClient.get(uri, headers: reqHeaders).timeout(_timeout);
      return _handleResponse(response);
    } on SocketException catch (_) {
      throw const ApiException('Unable to connect to SplitUp server. Please check your network connection.');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out while contacting server. Please try again.');
    }
  }

  Future<dynamic> post(
    String endpoint, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final extra = <String, String>{
      'Idempotency-Key': _generateIdempotencyKey(),
      ...?headers,
    };
    final reqHeaders = await _getHeaders(extraHeaders: extra);

    try {
      final response = await _activeClient
          .post(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null)
          .timeout(_timeout);
      return _handleResponse(response);
    } on SocketException catch (_) {
      throw const ApiException('Unable to connect to SplitUp server. Please check your network connection.');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out while contacting server. Please try again.');
    }
  }

  Future<dynamic> patch(
    String endpoint, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final extra = <String, String>{
      'Idempotency-Key': _generateIdempotencyKey(),
      ...?headers,
    };
    final reqHeaders = await _getHeaders(extraHeaders: extra);

    try {
      final response = await _activeClient
          .patch(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null)
          .timeout(_timeout);
      return _handleResponse(response);
    } on SocketException catch (_) {
      throw const ApiException('Unable to connect to SplitUp server. Please check your network connection.');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out while contacting server. Please try again.');
    }
  }

  Future<dynamic> delete(
    String endpoint, [
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  ]) async {
    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl$endpoint');
    final extra = <String, String>{
      'Idempotency-Key': _generateIdempotencyKey(),
      ...?headers,
    };
    final reqHeaders = await _getHeaders(extraHeaders: extra);

    try {
      final response = await _activeClient
          .delete(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null)
          .timeout(_timeout);
      return _handleResponse(response);
    } on SocketException catch (_) {
      throw const ApiException('Unable to connect to SplitUp server. Please check your network connection.');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out while contacting server. Please try again.');
    }
  }
}
