import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

/// Real backend authentication service connecting to the SplitUp Node.js + MySQL API.
/// Persists all accounts to Cloud MySQL database.
class ApiAuthService implements AuthService {
  static const _kPrefToken = 'splitup_auth_token';
  static const _kPrefUserId = 'splitup_user_id';
  static const _kPrefUserName = 'splitup_user_name';
  static const _kPrefUserPhone = 'splitup_user_phone';
  static const _kPrefUserEmail = 'splitup_user_email';

  final http.Client _client = http.Client();
  final Duration _timeout = const Duration(seconds: 12);

  Future<void> _saveSession(AuthUserProfile user, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefToken, token);
      await prefs.setString(_kPrefUserId, user.id);
      await prefs.setString(_kPrefUserName, user.name);
      await prefs.setString(_kPrefUserPhone, user.phoneE164);
      if (user.email != null && user.email!.isNotEmpty) {
        await prefs.setString(_kPrefUserEmail, user.email!);
      } else {
        await prefs.remove(_kPrefUserEmail);
      }
    } catch (_) {}
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
    return 'Server request failed with code $statusCode';
  }

  @override
  Future<AuthUserProfile> register({
    required String name,
    required String phone,
    String? email,
    required String password,
  }) async {
    final cleanPhone = normalizePhone(phone);
    if (cleanPhone.length != 10) {
      throw const AuthException('Please enter a valid 10-digit mobile number.');
    }
    if (name.trim().isEmpty) {
      throw const AuthException('Please enter your full name.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters long.');
    }

    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl/v1/users/auth/register');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name.trim(),
              'phone': cleanPhone,
              'email': email?.trim().isEmpty == true ? null : email?.trim(),
              'password': password,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body)['data'];
        final userJson = data['user'];
        final token = data['token'] as String? ?? 'Bearer user:${userJson['id']}';

        final user = AuthUserProfile.fromJson(userJson as Map<String, dynamic>);
        await _saveSession(user, token);
        return user;
      } else {
        throw AuthException(_extractErrorMessage(response.body, response.statusCode));
      }
    } on SocketException catch (_) {
      throw AuthException(
        'Unable to connect to SplitUp server ($baseUrl).\nPlease ensure your phone is connected to the same Wi-Fi network.',
      );
    } on TimeoutException catch (_) {
      throw AuthException('Connection timed out while contacting server ($baseUrl).');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Network error: ${e.toString()}');
    }
  }

  @override
  Future<AuthUserProfile> login({
    required String phone,
    required String password,
  }) async {
    final cleanPhone = normalizePhone(phone);
    if (cleanPhone.length != 10) {
      throw const AuthException('Please enter a valid 10-digit mobile number.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl/v1/users/auth/login');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': cleanPhone,
              'password': password,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final userJson = data['user'];
        final token = data['token'] as String? ?? 'Bearer user:${userJson['id']}';

        final user = AuthUserProfile.fromJson(userJson as Map<String, dynamic>);
        await _saveSession(user, token);
        return user;
      } else {
        throw AuthException(_extractErrorMessage(response.body, response.statusCode));
      }
    } on SocketException catch (_) {
      throw AuthException(
        'Unable to connect to SplitUp server ($baseUrl).\nPlease ensure your phone is connected to the same Wi-Fi network.',
      );
    } on TimeoutException catch (_) {
      throw AuthException('Connection timed out while contacting server ($baseUrl).');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Network error: ${e.toString()}');
    }
  }

  @override
  Future<void> sendOtp(String rawPhone) async {
    final cleaned = normalizePhone(rawPhone);
    if (cleaned.length != 10) {
      throw const AuthException('Please enter a valid 10-digit mobile number.');
    }
    // Simulated SMS gateway in development
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<bool> verifyOtpOnly(String rawPhone, String otp) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trimmed = otp.trim();
    if (trimmed == '123456' || trimmed == '000000') {
      return true;
    }
    throw const AuthException('Invalid verification code (Test code: 123456).');
  }

  @override
  Future<AuthVerificationResult> verifyOtp(String rawPhone, String otp) async {
    final cleaned = normalizePhone(rawPhone);
    await verifyOtpOnly(rawPhone, otp);

    final baseUrl = await ApiConfig.getBaseUrl();
    final uri = Uri.parse('$baseUrl/v1/users/auth/verify');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': cleaned}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final userJson = data['user'];
        final token = data['token'] as String? ?? 'Bearer user:${userJson['id']}';
        final user = AuthUserProfile.fromJson(userJson as Map<String, dynamic>);

        AuthMergeSummary? mergeSummary;
        if (data['mergeSummary'] != null) {
          mergeSummary = AuthMergeSummary.fromJson(data['mergeSummary'] as Map<String, dynamic>);
        }

        await _saveSession(user, token);

        return AuthVerificationResult(
          user: user,
          token: token,
          mergeSummary: mergeSummary,
        );
      } else {
        throw AuthException(_extractErrorMessage(response.body, response.statusCode));
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('OTP verification failed: ${e.toString()}');
    }
  }

  @override
  Future<AuthVerificationResult> signInWithGoogle() async {
    // For demo/dev purposes, use primary seed user
    const demoUser = AuthUserProfile(
      id: 'usr_arhaam',
      name: 'Arhaam',
      phoneE164: '+919876543210',
      email: 'arhaam@example.com',
    );
    await _saveSession(demoUser, 'Bearer user:usr_arhaam');
    return const AuthVerificationResult(
      user: demoUser,
      token: 'Bearer user:usr_arhaam',
      mergeSummary: null,
    );
  }

  @override
  Future<AuthUserProfile?> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kPrefToken);
      final id = prefs.getString(_kPrefUserId);
      final name = prefs.getString(_kPrefUserName);
      final phone = prefs.getString(_kPrefUserPhone);
      final email = prefs.getString(_kPrefUserEmail);

      if (token != null && id != null && name != null && phone != null) {
        return AuthUserProfile(
          id: id,
          name: name,
          phoneE164: phone,
          email: email,
        );
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefToken);
      await prefs.remove(_kPrefUserId);
      await prefs.remove(_kPrefUserName);
      await prefs.remove(_kPrefUserPhone);
      await prefs.remove(_kPrefUserEmail);
    } catch (_) {}
  }

  @override
  Future<List<StoredUserAccount>> getStoredAccounts() async {
    // Return standard demo accounts for fast switcher
    return const [
      StoredUserAccount(
        id: 'usr_arhaam',
        name: 'Arhaam',
        phone: '9876543210',
        email: 'arhaam@example.com',
        password: 'password123',
      ),
      StoredUserAccount(
        id: 'usr_rahul',
        name: 'Rahul',
        phone: '9876543211',
        email: 'rahul@example.com',
        password: 'password123',
      ),
      StoredUserAccount(
        id: 'usr_priya',
        name: 'Priya',
        phone: '9876543212',
        email: 'priya@example.com',
        password: 'password123',
      ),
    ];
  }
}
