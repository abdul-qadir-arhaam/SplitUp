import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // Attempt session restore on startup
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

  Future<void> sendOtp(String phone) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      await service.sendOtp(phone);
      state = const AuthState.unauthenticated();
    } catch (e) {
      state = AuthState.error(e.toString());
    }
  }

  Future<AuthVerificationResult?> verifyOtp(String phone, String otp) async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final result = await service.verifyOtp(phone, otp);
      state = AuthState.authenticated(result.user, result.mergeSummary);
      return result;
    } catch (e) {
      state = AuthState.error(e.toString());
      return null;
    }
  }

  Future<AuthVerificationResult?> signInWithGoogle() async {
    state = const AuthState.loading();
    try {
      final service = ref.read(authServiceProvider);
      final result = await service.signInWithGoogle();
      state = AuthState.authenticated(result.user, result.mergeSummary);
      return result;
    } catch (e) {
      state = AuthState.error(e.toString());
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
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
