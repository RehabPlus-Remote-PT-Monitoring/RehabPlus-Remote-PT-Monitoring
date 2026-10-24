import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/diagnostic_logger.dart';

/// The patient's round profile picture, or a person icon when none is set
/// (or when the stored bytes can't be decoded).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.photo,
    required this.size,
    this.onHeader = false,
  });

  final Uint8List? photo;
  final double size;

  /// Drawn on the teal profile header (translucent ring instead of a shadow).
  final bool onHeader;

  @override
  Widget build(BuildContext context) {
    final image = photo;
    final placeholder = Icon(Icons.person, size: size * 0.52, color: Colors.white);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: onHeader
            ? null
            : const LinearGradient(
                colors: [Color(0xFF23A8AA), Color(0xFF0D6E71)],
              ),
        color: onHeader ? Colors.white.withValues(alpha: 0.2) : null,
        border: onHeader
            ? Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2)
            : null,
        boxShadow: onHeader
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF23A8AA).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipOval(
        child: image == null
            ? placeholder
            : Image.memory(
                image,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                // Decode at display size, not the stored 512 px.
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                // A corrupt or unsupported image falls back to the icon
                // instead of Flutter's broken-image box.
                errorBuilder: (context, error, stackTrace) {
                  DiagnosticLogger.I.warn(
                    'ProfileAvatar',
                    'Profile photo could not be decoded',
                    {'bytes': image.length},
                    error,
                    stackTrace,
                  );
                  return placeholder;
                },
              ),
      ),
    );
  }
}
