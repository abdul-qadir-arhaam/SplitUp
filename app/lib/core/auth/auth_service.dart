import 'package:shared_preferences/shared_preferences.dart';

class AuthUserProfile {
  final String id;
  final String name;
  final String phoneE164;
  final String? email;
  final String? photoUrl;
  final bool isPlaceholder;

  const AuthUserProfile({
    required this.id,
    required this.name,
    required this.phoneE164,
    this.email,
    this.photoUrl,
    this.isPlaceholder = false,
  });

  factory AuthUserProfile.fromJson(Map<String, dynamic> json) {
    return AuthUserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneE164: json['phoneE164'] as String,
      email: json['email'] as String?,
      photoUrl: json['photoUrl'] as String?,
      isPlaceholder: json['isPlaceholder'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phoneE164': phoneE164,
    'email': email,
    'photoUrl': photoUrl,
    'isPlaceholder': isPlaceholder,
  };
}

class AuthMergeSummary {
  final bool merged;
  final String? placeholderId;
  final int expenseCount;
  final int totalPaise;

  const AuthMergeSummary({
    required this.merged,
    this.placeholderId,
    required this.expenseCount,
    required this.totalPaise,
  });

  factory AuthMergeSummary.fromJson(Map<String, dynamic> json) {
    return AuthMergeSummary(
      merged: json['merged'] as bool? ?? false,
      placeholderId: json['placeholderId'] as String?,
      expenseCount: (json['expenseCount'] as num?)?.toInt() ?? 0,
      totalPaise: (json['totalPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class AuthVerificationResult {
  final AuthUserProfile user;
  final AuthMergeSummary? mergeSummary;
  final String token;

  const AuthVerificationResult({
    required this.user,
    this.mergeSummary,
    required this.token,
  });
}

abstract class AuthService {
  Future<void> sendOtp(String rawPhone);
  Future<AuthVerificationResult> verifyOtp(String rawPhone, String otp);
  Future<AuthVerificationResult> signInWithGoogle();
  Future<AuthUserProfile?> restoreSession();
  Future<void> signOut();
}

/// Pluggable development and test stub for authentication.
/// Allows seamless offline development, QA test numbers, and test assertions.
class StubAuthService implements AuthService {
  static const _kPrefToken = 'splitup_auth_token';
  static const _kPrefUserId = 'splitup_user_id';
  static const _kPrefUserName = 'splitup_user_name';
  static const _kPrefUserPhone = 'splitup_user_phone';

  @override
  Future<void> sendOtp(String rawPhone) async {
    // In stub mode, instantly accept OTP request
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<AuthVerificationResult> verifyOtp(String rawPhone, String otp) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Normalize phone
    final cleaned = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
    final phone = cleaned.startsWith('91') ? '+$cleaned' : '+91$cleaned';

    final userId = 'usr_${cleaned.substring(cleaned.length >= 6 ? cleaned.length - 6 : 0)}';
    final user = AuthUserProfile(
      id: userId,
      name: 'User ${cleaned.substring(cleaned.length >= 4 ? cleaned.length - 4 : 0)}',
      phoneE164: phone,
    );

    // Save session
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefToken, 'Bearer user:$userId');
      await prefs.setString(_kPrefUserId, userId);
      await prefs.setString(_kPrefUserName, user.name);
      await prefs.setString(_kPrefUserPhone, phone);
    } catch (_) {}

    return AuthVerificationResult(
      user: user,
      token: 'Bearer user:$userId',
      mergeSummary: null,
    );
  }

  @override
  Future<AuthVerificationResult> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 300));
    const user = AuthUserProfile(
      id: 'usr_arhaam',
      name: 'Arhaam',
      phoneE164: '+919876543210',
      email: 'arhaam@splitup.app',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefToken, 'Bearer user:usr_arhaam');
      await prefs.setString(_kPrefUserId, user.id);
      await prefs.setString(_kPrefUserName, user.name);
      await prefs.setString(_kPrefUserPhone, user.phoneE164);
    } catch (_) {}

    return const AuthVerificationResult(
      user: user,
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

      if (token != null && id != null && name != null && phone != null) {
        return AuthUserProfile(id: id, name: name, phoneE164: phone);
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
    } catch (_) {}
  }
}
