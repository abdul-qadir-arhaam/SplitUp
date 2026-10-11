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
    return UserProfile(
      name: MockDataRepository.currentUser.name,
      phone: MockDataRepository.currentUser.phone,
      upiId: 'arhaam@okhdfcbank',
      photoUrl: MockDataRepository.currentUser.photoUrl,
    );
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kProfileNameKey);
      final phone = prefs.getString(_kProfilePhoneKey);
      final email = prefs.getString(_kProfileEmailKey);
      final upi = prefs.getString(_kProfileUpiKey);
      final photo = prefs.getString(_kProfilePhotoKey);

      state = UserProfile(
        name: name ?? state.name,
        phone: phone ?? state.phone,
        email: email ?? state.email,
        upiId: upi ?? state.upiId,
        photoUrl: photo ?? state.photoUrl,
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
