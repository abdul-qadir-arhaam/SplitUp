import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/api_config.dart';
import '../data/installer_service.dart';
import '../domain/app_version_info.dart';

class UpdateState {
  final String currentVersion;
  final int currentBuildNumber;
  final bool isChecking;
  final bool isUpdateAvailable;
  final AppVersionInfo? info;
  final bool isDownloading;
  final double downloadProgress;
  final String? statusMessage;
  final String? errorMessage;
  final bool needsPermission;
  final String? downloadedApkPath;

  const UpdateState({
    required this.currentVersion,
    required this.currentBuildNumber,
    this.isChecking = false,
    this.isUpdateAvailable = false,
    this.info,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.statusMessage,
    this.errorMessage,
    this.needsPermission = false,
    this.downloadedApkPath,
  });

  UpdateState copyWith({
    String? currentVersion,
    int? currentBuildNumber,
    bool? isChecking,
    bool? isUpdateAvailable,
    AppVersionInfo? info,
    bool? isDownloading,
    double? downloadProgress,
    String? statusMessage,
    String? errorMessage,
    bool? needsPermission,
    String? downloadedApkPath,
  }) {
    return UpdateState(
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuildNumber: currentBuildNumber ?? this.currentBuildNumber,
      isChecking: isChecking ?? this.isChecking,
      isUpdateAvailable: isUpdateAvailable ?? this.isUpdateAvailable,
      info: info ?? this.info,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage ?? this.errorMessage,
      needsPermission: needsPermission ?? this.needsPermission,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
    );
  }
}

class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    _init();
    return const UpdateState(
      currentVersion: '1.0.2',
      currentBuildNumber: 3,
    );
  }

  Future<void> _init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!ref.mounted) return;
      final buildNum = int.tryParse(info.buildNumber) ?? 3;
      state = state.copyWith(
        currentVersion: info.version.isNotEmpty ? info.version : '1.0.2',
        currentBuildNumber: buildNum,
      );
      await checkForUpdate();
    } catch (_) {
      if (ref.mounted) {
        await checkForUpdate();
      }
    }
  }

  Future<void> checkForUpdate() async {
    if (!ref.mounted) return;
    state = state.copyWith(isChecking: true, errorMessage: null);
    try {
      final baseUrl = await ApiConfig.getBaseUrl();
      final uri = Uri.parse('$baseUrl/app/version');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (!ref.mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final versionInfo = AppVersionInfo.fromJson(
          json: data,
          currentVersion: state.currentVersion,
          currentBuildNumber: state.currentBuildNumber,
        );

        bool needsPermission = false;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          final canInstall = await InstallerService.canRequestPackageInstalls();
          if (!ref.mounted) return;
          needsPermission = !canInstall;
        }

        if (ref.mounted) {
          state = state.copyWith(
            isChecking: false,
            isUpdateAvailable: versionInfo.isUpdateAvailable,
            info: versionInfo,
            needsPermission: needsPermission,
          );
        }
      } else {
        if (ref.mounted) {
          state = state.copyWith(isChecking: false);
        }
      }
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          isChecking: false,
          errorMessage: 'Unable to check for updates: $e',
        );
      }
    }
  }

  Future<void> openInstallSettings() async {
    await InstallerService.openInstallPermissionSettings();
    final canInstall = await InstallerService.canRequestPackageInstalls();
    state = state.copyWith(needsPermission: !canInstall);
  }

  Future<void> checkInstallPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final canInstall = await InstallerService.canRequestPackageInstalls();
      state = state.copyWith(needsPermission: !canInstall);
    }
  }

  Future<void> installDownloadedApk() async {
    final path = state.downloadedApkPath;
    if (path == null) {
      startOtaUpdate();
      return;
    }

    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      startOtaUpdate();
      return;
    }

    final canInstall = await InstallerService.canRequestPackageInstalls();
    if (!canInstall) {
      state = state.copyWith(
        needsPermission: true,
        errorMessage: 'Permission required: SplitUp needs permission to install app updates. Please allow "Install unknown apps" in Settings.',
      );
      await InstallerService.openInstallPermissionSettings();
      return;
    }

    state = state.copyWith(
      statusMessage: 'Opening package installer...',
      errorMessage: null,
    );

    final success = await InstallerService.installApk(path);
    if (!success) {
      state = state.copyWith(
        errorMessage: 'Could not launch installer. Falling back to browser download...',
      );
      final downloadUrl = state.info?.downloadUrl;
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> startOtaUpdate() async {
    final info = state.info;
    if (info == null || info.downloadUrl.isEmpty) return;

    // Fallback for non-Android platforms (e.g. Chrome / Web)
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
      return;
    }

    // Step 1: Check permission before starting download
    final canInstall = await InstallerService.canRequestPackageInstalls();
    if (!canInstall) {
      state = state.copyWith(
        needsPermission: true,
        errorMessage: 'Install permission required: SplitUp needs permission to install updates. Please enable "Allow from this source" in Settings.',
      );
      await InstallerService.openInstallPermissionSettings();
      return;
    }

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      statusMessage: 'Connecting to download server...',
      errorMessage: null,
      needsPermission: false,
    );

    try {
      final downloadPath = await InstallerService.getDownloadPath();
      if (downloadPath == null) {
        throw Exception('Unable to resolve download storage path on device');
      }

      final file = File(downloadPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
        client.close();
        throw Exception('Download server returned HTTP status ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      final sink = file.openWrite();
      int bytesReceived = 0;
      int lastReportedPercent = -1;

      await streamedResponse.stream.listen(
        (List<int> chunk) {
          bytesReceived += chunk.length;
          sink.add(chunk);

          if (contentLength > 0) {
            final progress = (bytesReceived / contentLength).clamp(0.0, 1.0);
            final percent = (progress * 100).toInt();
            if (percent != lastReportedPercent && ref.mounted) {
              lastReportedPercent = percent;
              state = state.copyWith(
                isDownloading: true,
                downloadProgress: progress,
                statusMessage: 'Downloading update ($percent%)...',
              );
            }
          } else if (ref.mounted) {
            state = state.copyWith(
              isDownloading: true,
              downloadProgress: 0.5,
              statusMessage: 'Downloading update...',
            );
          }
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();
      client.close();

      final bytesOnDisk = await file.length();
      debugPrint('[SplitUpInstaller] Download finished: $downloadPath ($bytesOnDisk bytes)');

      if (bytesOnDisk <= 0) {
        throw Exception('Downloaded file is empty (0 bytes)');
      }

      if (ref.mounted) {
        state = state.copyWith(
          isDownloading: false,
          downloadProgress: 1.0,
          downloadedApkPath: downloadPath,
          statusMessage: 'Opening installer...',
        );
      }

      // Verify permission once more before launching installer
      final verifiedCanInstall = await InstallerService.canRequestPackageInstalls();
      if (!verifiedCanInstall) {
        if (ref.mounted) {
          state = state.copyWith(
            needsPermission: true,
            errorMessage: 'Permission required: Please enable "Allow from this source" in Settings to finish installing.',
          );
        }
        await InstallerService.openInstallPermissionSettings();
        return;
      }

      // Launch modern Android Intent.ACTION_VIEW with FileProvider
      final success = await InstallerService.installApk(downloadPath);
      if (!success) {
        if (ref.mounted) {
          state = state.copyWith(
            errorMessage: 'Could not launch package installer. Falling back to browser download...',
          );
        }
        launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[SplitUpInstaller] Error during update: $e');
      if (ref.mounted) {
        state = state.copyWith(
          isDownloading: false,
          errorMessage: 'Download failed: $e. Opening browser download...',
        );
      }
      launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
    }
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
