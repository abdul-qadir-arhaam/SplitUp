import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/profile/data/user_profile_provider.dart';
import 'auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final AuthUserProfile? user;
  final AuthMergeSummary? mergeSummary;
  final String? errorMessage;

  const AuthState({
    required this.status,
    this.user,
    this.mergeSummary,
    this.errorMessage,
  });

  const AuthState.initial() : this(status: AuthStatus.initial);
  const AuthState.loading() : this(status: AuthStatus.loading);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);
  const AuthState.authenticated(AuthUserProfile user, [AuthMergeSummary? mergeSummary])
      : this(status: AuthStatus.authenticated, user: user, mergeSummary: mergeSummary);
  const AuthState.error(String message)
      : this(status: AuthStatus.error, errorMessage: message);

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
}

final authServiceProvider = Provider<AuthService>((ref) {
  return StubAuthService();
});

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthState.initial();
  }

  Future<void> _restoreSession() async {
    final service = ref.read(authServiceProvider);
    final user = await service.restoreSession();
    if (user != null) {
      state = AuthState.authenticated(user);
    } else {
      state = const AuthState.unauthenticated();
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = AuthState(
        status: state.user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
        user: state.user,
        mergeSummary: state.mergeSummary,
        errorMessage: null,
      );
    }
  }

  Future<void> sendOtp(String phone) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      await service.sendOtp(phone);
      state = const AuthState.unauthenticated();
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      rethrow;
    }
  }

  Future<bool> verifyOtpOnly(String phone, String otp) async {
    try {
      final service = ref.read(authServiceProvider);
      return await service.verifyOtpOnly(phone, otp);
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      rethrow;
    }
  }

  Future<AuthVerificationResult?> verifyOtp(String phone, String otp) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final result = await service.verifyOtp(phone, otp);
      state = AuthState.authenticated(result.user, result.mergeSummary);
      _syncProfile(result.user);
      return result;
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      return null;
    }
  }

  Future<AuthUserProfile> register({
    required String name,
    required String phone,
    String? email,
    required String password,
  }) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final user = await service.register(
        name: name,
        phone: phone,
        email: email,
        password: password,
      );
      state = AuthState.authenticated(user);
      _syncProfile(user);
      return user;
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      rethrow;
    }
  }

  Future<AuthUserProfile> login({
    required String phone,
    required String password,
  }) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final user = await service.login(phone: phone, password: password);
      state = AuthState.authenticated(user);
      _syncProfile(user);
      return user;
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      rethrow;
    }
  }

  Future<AuthVerificationResult?> signInWithGoogle() async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final result = await service.signInWithGoogle();
      state = AuthState.authenticated(result.user, result.mergeSummary);
      _syncProfile(result.user);
      return result;
    } catch (e) {
      final msg = e is AuthException ? e.message : e.toString();
      state = AuthState.error(msg);
      return null;
    }
  }

  Future<void> signOut() async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      await service.signOut();
      state = const AuthState.unauthenticated();
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }

  void _syncProfile(AuthUserProfile user) {
    try {
      ref.read(userProfileProvider.notifier).updateProfile(
            name: user.name,
            phone: user.phoneE164,
            email: user.email,
            photoUrl: user.photoUrl,
          );
    } catch (_) {}
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
