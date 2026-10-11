class FriendModel {
  final String id;
  final String name;
  final String phoneE164;
  final String? photoUrl;
  final bool isAppUser;
  final String? nickname;
  final String? contactName;
  final String individualLedgerId;
  final int netPaise;
  final List<String> commonGroups;

  const FriendModel({
    required this.id,
    required this.name,
    required this.phoneE164,
    this.photoUrl,
    required this.isAppUser,
    this.nickname,
    this.contactName,
    required this.individualLedgerId,
    required this.netPaise,
    this.commonGroups = const [],
  });

  /// Name resolution precedence: Nickname -> Contact Name -> Profile Name
  String get resolvedName {
    if (nickname != null && nickname!.trim().isNotEmpty) {
      return nickname!.trim();
    }
    if (contactName != null && contactName!.trim().isNotEmpty) {
      return contactName!.trim();
    }
    return name;
  }

  FriendModel copyWith({
    String? name,
    String? nickname,
    String? contactName,
    int? netPaise,
    bool? isAppUser,
    List<String>? commonGroups,
  }) {
    return FriendModel(
      id: id,
      name: name ?? this.name,
      phoneE164: phoneE164,
      photoUrl: photoUrl,
      isAppUser: isAppUser ?? this.isAppUser,
      nickname: nickname ?? this.nickname,
      contactName: contactName ?? this.contactName,
      individualLedgerId: individualLedgerId,
      netPaise: netPaise ?? this.netPaise,
      commonGroups: commonGroups ?? this.commonGroups,
    );
  }

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    return FriendModel(
      id: (json['friendId'] ?? json['id']) as String,
      name: json['name'] as String,
      phoneE164: (json['phoneE164'] ?? json['phone']) as String,
      photoUrl: json['photoUrl'] as String?,
      isAppUser: json['isAppUser'] as bool? ?? true,
      nickname: json['nickname'] as String?,
      contactName: json['contactName'] as String?,
      individualLedgerId: (json['individualLedgerId'] ?? '') as String,
      netPaise: (json['netPaise'] as num?)?.toInt() ?? 0,
      commonGroups: (json['commonGroups'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneE164': phoneE164,
        'photoUrl': photoUrl,
        'isAppUser': isAppUser,
        'nickname': nickname,
        'contactName': contactName,
        'individualLedgerId': individualLedgerId,
        'netPaise': netPaise,
        'commonGroups': commonGroups,
      };
}
