import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class StoredUserAccount {
  final String id;
  final String name;
  final String phone; // 10-digit normalized phone number
  final String? email;
  final String password;
  final String? photoUrl;

  const StoredUserAccount({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.password,
    this.photoUrl,
  });

  factory StoredUserAccount.fromJson(Map<String, dynamic> json) {
    return StoredUserAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      password: json['password'] as String,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'password': password,
    'photoUrl': photoUrl,
  };
}

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
  Future<bool> verifyOtpOnly(String rawPhone, String otp);
  Future<AuthVerificationResult> verifyOtp(String rawPhone, String otp);
  Future<AuthUserProfile> register({
    required String name,
    required String phone,
    String? email,
    required String password,
  });
  Future<AuthUserProfile> login({
    required String phone,
    required String password,
  });
  Future<AuthVerificationResult> signInWithGoogle();
  Future<AuthUserProfile?> restoreSession();
  Future<void> signOut();
  Future<List<StoredUserAccount>> getStoredAccounts();
}

/// Helper to normalize any phone string to a clean 10-digit format
String normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 10) {
    return digits.substring(digits.length - 10);
  }
  return digits;
}

/// Pluggable authentication service with persistent local storage.
/// Supports account registration with OTP verification, phone+password login,
/// and session persistence across app restarts.
class StubAuthService implements AuthService {
  static const _kPrefToken = 'splitup_auth_token';
  static const _kPrefUserId = 'splitup_user_id';
  static const _kPrefUserName = 'splitup_user_name';
  static const _kPrefUserPhone = 'splitup_user_phone';
  static const _kPrefUserEmail = 'splitup_user_email';
  static const _kPrefAccountsKey = 'splitup_registered_users_v2';

  // Seed default demo account
  static final StoredUserAccount _defaultUser = StoredUserAccount(
    id: 'usr_arhaam',
    name: 'Arhaam',
    phone: '9876543210',
    email: 'arhaam@splitup.app',
    password: 'password123',
  );

  Future<List<StoredUserAccount>> _loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefAccountsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final list = decoded
            .map((e) => StoredUserAccount.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return [_defaultUser];
  }

  Future<void> _saveAccounts(List<StoredUserAccount> accounts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = accounts.map((a) => a.toJson()).toList();
      await prefs.setString(_kPrefAccountsKey, jsonEncode(jsonList));
    } catch (_) {}
  }

  @override
  Future<List<StoredUserAccount>> getStoredAccounts() async {
    return _loadAccounts();
  }

  @override
  Future<void> sendOtp(String rawPhone) async {
    final cleaned = normalizePhone(rawPhone);
    if (cleaned.length != 10) {
      throw const AuthException('Please enter a valid 10-digit mobile number.');
    }
    // Simulate SMS dispatch latency
    await Future.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<bool> verifyOtpOnly(String rawPhone, String otp) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final trimmed = otp.trim();
    // In demo/test environment, standard OTP is 123456
    if (trimmed == '123456' || trimmed == '000000') {
      return true;
    }
    throw const AuthException('Invalid verification code. Please check and try again (Test code: 123456).');
  }

  @override
  Future<AuthVerificationResult> verifyOtp(String rawPhone, String otp) async {
    await verifyOtpOnly(rawPhone, otp);
    final cleaned = normalizePhone(rawPhone);
    final phone = '+91$cleaned';

    final userId = 'usr_${cleaned.substring(cleaned.length >= 6 ? cleaned.length - 6 : 0)}';
    final user = AuthUserProfile(
      id: userId,
      name: 'User ${cleaned.substring(cleaned.length >= 4 ? cleaned.length - 4 : 0)}',
      phoneE164: phone,
    );

    await _saveSession(user);

    return AuthVerificationResult(
      user: user,
      token: 'Bearer user:$userId',
      mergeSummary: null,
    );
  }

  @override
  Future<AuthUserProfile> register({
    required String name,
    required String phone,
    String? email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
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

    final accounts = await _loadAccounts();
    // Check if phone is already registered
    final existingIndex = accounts.indexWhere((a) => a.phone == cleanPhone);
    final newId = 'usr_${DateTime.now().millisecondsSinceEpoch}';
    final newAccount = StoredUserAccount(
      id: existingIndex != -1 ? accounts[existingIndex].id : newId,
      name: name.trim(),
      phone: cleanPhone,
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      password: password,
    );

    if (existingIndex != -1) {
      accounts[existingIndex] = newAccount;
    } else {
      accounts.insert(0, newAccount);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('splitup_friends_${newAccount.id}', '[]');
        await prefs.setString('splitup_groups_${newAccount.id}', '[]');
        await prefs.setString('splitup_trips_${newAccount.id}', '[]');
        await prefs.setString('splitup_expenses_${newAccount.id}', '[]');
        await prefs.setString('splitup_settlements_${newAccount.id}', '[]');
      } catch (_) {}
    }
    await _saveAccounts(accounts);

    final userProfile = AuthUserProfile(
      id: newAccount.id,
      name: newAccount.name,
      phoneE164: '+91$cleanPhone',
      email: newAccount.email,
    );

    await _saveSession(userProfile);
    return userProfile;
  }

  @override
  Future<AuthUserProfile> login({
    required String phone,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final cleanPhone = normalizePhone(phone);
    if (cleanPhone.length != 10) {
      throw const AuthException('Please enter a valid 10-digit mobile number.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    final accounts = await _loadAccounts();
    final matched = accounts.where((a) => a.phone == cleanPhone).toList();

    if (matched.isEmpty) {
      throw const AuthException('No account found for this mobile number. Please sign up first.');
    }

    final account = matched.first;
    if (account.password != password) {
      throw const AuthException('Incorrect password. Please try again.');
    }

    final userProfile = AuthUserProfile(
      id: account.id,
      name: account.name,
      phoneE164: '+91$cleanPhone',
      email: account.email,
      photoUrl: account.photoUrl,
    );

    await _saveSession(userProfile);
    return userProfile;
  }

  Future<void> _saveSession(AuthUserProfile user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefToken, 'Bearer user:${user.id}');
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

  @override
  Future<AuthVerificationResult> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 300));
    const user = AuthUserProfile(
      id: 'usr_arhaam',
      name: 'Arhaam',
      phoneE164: '+919876543210',
      email: 'arhaam@splitup.app',
    );

    await _saveSession(user);

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
}
