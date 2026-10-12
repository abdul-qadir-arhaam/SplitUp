import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/mock/mock_data.dart';

const _kProfileNameKey = 'splitup_profile_name';
const _kProfilePhoneKey = 'splitup_profile_phone';
const _kProfileEmailKey = 'splitup_profile_email';
const _kProfileUpiKey = 'splitup_profile_upi';
const _kProfilePhotoKey = 'splitup_profile_photo';

class UserProfile {
  final String name;
  final String phone;
  final String? email;
  final String upiId;
  final String? photoUrl;

  const UserProfile({
    required this.name,
    required this.phone,
    this.email,
    required this.upiId,
    this.photoUrl,
  });

  UserProfile copyWith({
    String? name,
    String? phone,
    String? email,
    String? upiId,
    String? photoUrl,
    bool clearPhoto = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      upiId: upiId ?? this.upiId,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
    );
  }
}

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    _loadProfile();
    return const UserProfile(
      name: 'User',
      phone: '',
      upiId: '',
      photoUrl: null,
    );
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      final isDemoUser = currentUserId == 'usr_arhaam';

      final name = prefs.getString(_kProfileNameKey) ?? prefs.getString('splitup_user_name');
      final phone = prefs.getString(_kProfilePhoneKey) ?? prefs.getString('splitup_user_phone');
      final email = prefs.getString(_kProfileEmailKey) ?? prefs.getString('splitup_user_email');
      final upi = prefs.getString(_kProfileUpiKey);
      final photo = prefs.getString(_kProfilePhotoKey);

      state = UserProfile(
        name: name ?? (isDemoUser ? 'Arhaam' : 'User'),
        phone: phone ?? (isDemoUser ? '+919876543210' : ''),
        email: email ?? (isDemoUser ? 'arhaam@splitup.app' : null),
        upiId: upi ?? (isDemoUser ? 'arhaam@okhdfcbank' : ''),
        photoUrl: photo ?? (isDemoUser ? MockDataRepository.currentUser.photoUrl : null),
      );
    } catch (_) {}
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? email,
    String? upiId,
    String? photoUrl,
    bool clearPhoto = false,
  }) async {
    final updated = state.copyWith(
      name: name,
      phone: phone,
      email: email,
      upiId: upiId,
      photoUrl: photoUrl,
      clearPhoto: clearPhoto,
    );
    state = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (name != null) await prefs.setString(_kProfileNameKey, name);
      if (phone != null) await prefs.setString(_kProfilePhoneKey, phone);
      if (email != null) await prefs.setString(_kProfileEmailKey, email);
      if (upiId != null) await prefs.setString(_kProfileUpiKey, upiId);
      if (clearPhoto) {
        await prefs.remove(_kProfilePhotoKey);
      } else if (photoUrl != null) {
        await prefs.setString(_kProfilePhotoKey, photoUrl);
      }
    } catch (_) {}
  }
}

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});
