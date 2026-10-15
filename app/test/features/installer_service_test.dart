import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/update/data/installer_service.dart';
import 'package:app/features/update/presentation/update_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.splitup.app/installer');
  final log = <MethodCall>[];
  bool mockCanInstall = true;
  bool mockInstallSuccess = true;

  setUp(() {
    log.clear();
    mockCanInstall = true;
    mockInstallSuccess = true;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'canRequestPackageInstalls':
          return mockCanInstall;
        case 'openInstallPermissionSettings':
          return true;
        case 'getDownloadPath':
          return '/mock/path/ota_update/splitup-update.apk';
        case 'installApk':
          return mockInstallSuccess;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('InstallerService MethodChannel Tests', () {
    test('canRequestPackageInstalls returns true when granted', () async {
      mockCanInstall = true;
      final result = await InstallerService.canRequestPackageInstalls();
      expect(result, isTrue);
      expect(log.any((call) => call.method == 'canRequestPackageInstalls'), isTrue);
    });

    test('canRequestPackageInstalls returns false when not granted', () async {
      mockCanInstall = false;
      final result = await InstallerService.canRequestPackageInstalls();
      expect(result, isFalse);
    });

    test('openInstallPermissionSettings invokes native settings intent', () async {
      final result = await InstallerService.openInstallPermissionSettings();
      expect(result, isTrue);
      expect(log.any((call) => call.method == 'openInstallPermissionSettings'), isTrue);
    });

    test('getDownloadPath returns resolved internal file path', () async {
      final path = await InstallerService.getDownloadPath();
      expect(path, equals('/mock/path/ota_update/splitup-update.apk'));
    });

    test('installApk passes filePath to native channel and returns success', () async {
      mockInstallSuccess = true;
      final result = await InstallerService.installApk('/mock/path/ota_update/splitup-update.apk');
      expect(result, isTrue);
      final installCall = log.firstWhere((c) => c.method == 'installApk');
      expect(installCall.arguments['filePath'], equals('/mock/path/ota_update/splitup-update.apk'));
    });
  });

  group('UpdateController Integration Tests', () {
    test('initial state has default version and idle status', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(updateControllerProvider);
      expect(state.currentVersion, isNotEmpty);
      expect(state.isDownloading, isFalse);
      expect(state.downloadProgress, equals(0.0));
    });

    test('openInstallSettings toggles permission check', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      mockCanInstall = true;
      await container.read(updateControllerProvider.notifier).openInstallSettings();

      final state = container.read(updateControllerProvider);
      expect(state.needsPermission, isFalse);
    });
  });
}
