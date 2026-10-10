/// Priority resolver for user names according to PRD & ARCHITECTURE.md:
/// 1. Nickname (private to the viewer)
/// 2. Contact name (synced from device contacts)
/// 3. Profile name (fallback registered user name)
class NameResolver {
  static String displayNameFor({
    String? nickname,
    String? contactName,
    required String profileName,
  }) {
    if (nickname != null && nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    if (contactName != null && contactName.trim().isNotEmpty) {
      return contactName.trim();
    }
    return profileName.trim().isNotEmpty ? profileName.trim() : 'Unknown';
  }
}

String displayNameFor({
  String? nickname,
  String? contactName,
  required String profileName,
}) =>
    NameResolver.displayNameFor(
      nickname: nickname,
      contactName: contactName,
      profileName: profileName,
    );
