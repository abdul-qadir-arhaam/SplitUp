import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import 'update_controller.dart';

class UpdateBottomSheet extends ConsumerWidget {
  const UpdateBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UpdateBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateControllerProvider);
    final colors = Theme.of(context).extension<SplitUpColors>() ??
        SplitUpColors.dark;
    final info = updateState.info;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceFlatRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: colors.divider),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.accentReceive.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.accentReceive.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  color: colors.accentReceive,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info?.isUpdateAvailable == true
                          ? 'Update Available'
                          : 'App Up to Date',
                      style: SplitUpTypography.title(color: colors.textPrimary)
                          .copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info?.isUpdateAvailable == true
                          ? 'Version ${info?.latestVersion} (Build ${info?.buildNumber})'
                          : 'You are on the latest version (${updateState.currentVersion})',
                      style: SplitUpTypography.caption(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              if (info != null && info.fileSizeMb > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlat,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Text(
                    '${info.fileSizeMb.toStringAsFixed(1)} MB',
                    style: SplitUpTypography.caption(color: colors.accentBrass)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Release Notes Box
          if (info != null && info.releaseNotes.isNotEmpty) ...[
            Text(
              "WHAT'S NEW",
              style: SplitUpTypography.caption(color: colors.textMuted)
                  .copyWith(letterSpacing: 1.1, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceFlat,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.divider),
              ),
              child: Text(
                info.releaseNotes,
                style: SplitUpTypography.body(color: colors.textSecondary)
                    .copyWith(fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Error message if any
          if (updateState.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.accentOwe.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.accentOwe.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                updateState.errorMessage!,
                style: SplitUpTypography.caption(color: colors.accentOwe),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action Button / Progress Area
          if (updateState.isDownloading) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      updateState.statusMessage ?? 'Downloading...',
                      style: SplitUpTypography.caption(color: colors.accentReceive)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${(updateState.downloadProgress * 100).toInt()}%',
                      style: SplitUpTypography.caption(color: colors.textPrimary)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: updateState.downloadProgress > 0
                        ? updateState.downloadProgress
                        : null,
                    backgroundColor: colors.surfaceFlat,
                    color: colors.accentReceive,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The installer will open automatically once downloaded.',
                  style: SplitUpTypography.caption(color: colors.textMuted)
                      .copyWith(fontSize: 11),
                ),
              ],
            ),
          ] else if (info?.isUpdateAvailable == true) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentReceive,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  'Download & Install Update',
                  style: SplitUpTypography.label(color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                onPressed: () {
                  ref.read(updateControllerProvider.notifier).startOtaUpdate();
                },
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: updateState.isChecking
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textMuted,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(
                  updateState.isChecking
                      ? 'Checking for updates...'
                      : 'Check Again',
                  style: SplitUpTypography.label(color: colors.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                onPressed: updateState.isChecking
                    ? null
                    : () {
                        ref
                            .read(updateControllerProvider.notifier)
                            .checkForUpdate();
                      },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
