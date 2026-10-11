import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

class Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final Uint8List? imageBytes;
  final double size;
  final bool isPlaceholder;

  const Avatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.imageBytes,
    this.size = 40,
    this.isPlaceholder = false,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    ImageProvider? imageProvider;
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      imageProvider = MemoryImage(imageBytes!);
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      if (photoUrl!.startsWith('data:image')) {
        try {
          final commaIndex = photoUrl!.indexOf(',');
          final base64Data = commaIndex != -1 ? photoUrl!.substring(commaIndex + 1) : photoUrl!;
          imageProvider = MemoryImage(base64Decode(base64Data));
        } catch (_) {
          imageProvider = null;
        }
      } else {
        imageProvider = NetworkImage(photoUrl!);
      }
    }

    if (imageProvider != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: imageProvider,
        onBackgroundImageError: (exception, stackTrace) {},
      );
    }

    final bg = isPlaceholder
        ? colors.surfaceFlatRaised
        : colors.accentBrass.withValues(alpha: 0.25);
    final textCol = isPlaceholder ? colors.textMuted : colors.accentBrass;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.glassBorder,
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: SplitUpTypography.label(color: textCol).copyWith(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
