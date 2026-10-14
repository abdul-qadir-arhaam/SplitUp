import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/api_config.dart';
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
      final buildNum = int.tryParse(info.buildNumber) ?? 3;
      state = state.copyWith(
        currentVersion: info.version.isNotEmpty ? info.version : '1.0.2',
        currentBuildNumber: buildNum,
      );
      await checkForUpdate();
    } catch (_) {
      await checkForUpdate();
    }
  }

  Future<void> checkForUpdate() async {
    state = state.copyWith(isChecking: true, errorMessage: null);
    try {
      final baseUrl = await ApiConfig.getBaseUrl();
      final uri = Uri.parse('$baseUrl/app/version');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final versionInfo = AppVersionInfo.fromJson(
          json: data,
          currentVersion: state.currentVersion,
          currentBuildNumber: state.currentBuildNumber,
        );

        state = state.copyWith(
          isChecking: false,
          isUpdateAvailable: versionInfo.isUpdateAvailable,
          info: versionInfo,
        );
      } else {
        state = state.copyWith(isChecking: false);
      }
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: 'Unable to check for updates: $e',
      );
    }
  }

  void startOtaUpdate() {
    final info = state.info;
    if (info == null || info.downloadUrl.isEmpty) return;

    // Fallback for non-Android platforms (e.g. Chrome / Web)
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
      return;
    }

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      statusMessage: 'Connecting...',
      errorMessage: null,
    );

    try {
      OtaUpdate().execute(
        info.downloadUrl,
        destinationFilename: 'splitup-update.apk',
      ).listen(
        (OtaEvent event) {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final parsed = int.tryParse(event.value ?? '0') ?? 0;
              final progress = (parsed / 100.0).clamp(0.0, 1.0);
              state = state.copyWith(
                isDownloading: true,
                downloadProgress: progress,
                statusMessage: 'Downloading update ($parsed%)...',
              );
              break;
            case OtaStatus.INSTALLING:
              state = state.copyWith(
                isDownloading: false,
                downloadProgress: 1.0,
                statusMessage: 'Ready to install',
              );
              break;
            case OtaStatus.ALREADY_RUNNING_ERROR:
              state = state.copyWith(
                isDownloading: false,
                statusMessage: 'An update is already in progress',
              );
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              state = state.copyWith(
                isDownloading: false,
                errorMessage: 'Install permission required to update.',
              );
              break;
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            default:
              state = state.copyWith(
                isDownloading: false,
                errorMessage: 'Download failed: ${event.value ?? 'network error'}. Falling back to browser...',
              );
              // Graceful fallback to browser
              launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
              break;
          }
        },
        onError: (e) {
          state = state.copyWith(
            isDownloading: false,
            errorMessage: 'Download error. Opening download link in browser...',
          );
          launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
        },
      );
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        errorMessage: 'Unable to start update: $e',
      );
      launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
    }
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
