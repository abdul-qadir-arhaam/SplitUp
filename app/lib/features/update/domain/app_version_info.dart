class AppVersionInfo {
  final String latestVersion;
  final int buildNumber;
  final int minSupportedBuild;
  final String downloadUrl;
  final double fileSizeMb;
  final String releaseNotes;
  final bool isUpdateAvailable;
  final String currentVersion;
  final int currentBuildNumber;

  const AppVersionInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.minSupportedBuild,
    required this.downloadUrl,
    required this.fileSizeMb,
    required this.releaseNotes,
    required this.isUpdateAvailable,
    required this.currentVersion,
    required this.currentBuildNumber,
  });

  factory AppVersionInfo.fromJson({
    required Map<String, dynamic> json,
    required String currentVersion,
    required int currentBuildNumber,
  }) {
    final latestVersion = (json['latest_version'] ?? json['currentVersion'] ?? '1.0.0').toString();
    final buildNumber = (json['build_number'] ?? json['buildNumber'] ?? 1) as int;
    final minSupported = (json['min_supported_build'] ?? json['minSupportedVersionCode'] ?? 1) as int;
    final downloadUrl = (json['download_url'] ?? json['downloadUrl'] ?? '').toString();
    final fileSizeMb = ((json['file_size_mb'] ?? 20.48) as num).toDouble();
    final releaseNotes = (json['release_notes'] ?? json['releaseNotes'] ?? '').toString();

    final isUpdateAvailable = buildNumber > currentBuildNumber;

    return AppVersionInfo(
      latestVersion: latestVersion,
      buildNumber: buildNumber,
      minSupportedBuild: minSupported,
      downloadUrl: downloadUrl,
      fileSizeMb: fileSizeMb,
      releaseNotes: releaseNotes,
      isUpdateAvailable: isUpdateAvailable,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
    );
  }
}
