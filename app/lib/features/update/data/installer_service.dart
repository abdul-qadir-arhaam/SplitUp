import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class InstallerService {
  static const MethodChannel _channel = MethodChannel('com.splitup.app/installer');

  static Future<bool> canRequestPackageInstalls() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? false;
    } catch (e) {
      debugPrint('[InstallerService] canRequestPackageInstalls error: $e');
      return true;
    }
  }

  static Future<bool> openInstallPermissionSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('openInstallPermissionSettings');
      return res ?? false;
    } catch (e) {
      debugPrint('[InstallerService] openInstallPermissionSettings error: $e');
      return false;
    }
  }

  static Future<String?> getDownloadPath() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('getDownloadPath');
    } catch (e) {
      debugPrint('[InstallerService] getDownloadPath error: $e');
      return null;
    }
  }

  static Future<bool> installApk(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[InstallerService] installApk error: $e');
      return false;
    }
  }
}
