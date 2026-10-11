import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setOffline(bool offline) => state = offline;
}

final isOfflineProvider = NotifierProvider<OfflineNotifier, bool>(OfflineNotifier.new);

class UpdateAvailableNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setUpdate(String? version) => state = version;
}

final updateAvailableProvider = NotifierProvider<UpdateAvailableNotifier, String?>(UpdateAvailableNotifier.new);

class AppStatusBanner extends ConsumerWidget {
  const AppStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isOffline = ref.watch(isOfflineProvider);
    final updateVersion = ref.watch(updateAvailableProvider);

    if (isOffline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colors.statusWarn.withValues(alpha: 0.16),
          border: Border(
            bottom: BorderSide(
              color: colors.statusWarn.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, size: 14, color: colors.statusWarn),
              const SizedBox(width: 8),
              Text(
                "You're offline. Showing saved data.",
                style: SplitUpTypography.caption(color: colors.statusWarn).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (updateVersion != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colors.accentBrass.withValues(alpha: 0.18),
          border: Border(
            bottom: BorderSide(
              color: colors.accentBrass.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update_rounded, size: 16, color: colors.accentBrass),
                  const SizedBox(width: 8),
                  Text(
                    'Update available: SplitUp $updateVersion',
                    style: SplitUpTypography.caption(color: colors.textPrimary).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surfaceFlatRaised,
                      content: Text(
                        'Download the latest update from the website.',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'UPDATE',
                    style: SplitUpTypography.caption(color: colors.accentBrass).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
