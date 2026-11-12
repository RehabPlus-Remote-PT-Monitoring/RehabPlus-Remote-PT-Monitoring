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

  /// Photos whose decode failure was already logged. Flutter calls the error
  /// builder again on every rebuild of every avatar showing the same broken
  /// photo (profile header, account info, ...), which would repeat the same
  /// warning many times; one record per photo is enough. An Expando holds
  /// its keys weakly, so this never keeps a (personal) photo in memory.
  static final Expando<bool> _reported = Expando('ProfileAvatar.reported');

  /// Logs a photo that can't be decoded, once per photo. Returns whether it
  /// logged (for tests).
  @visibleForTesting
  static bool reportUndecodablePhoto(
    Uint8List photo,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (_reported[photo] == true) return false;
    _reported[photo] = true;
    DiagnosticLogger.I.warn(
      'ProfileAvatar',
      'Profile photo could not be decoded',
      {'bytes': photo.length},
      error,
      stackTrace,
    );
    return true;
  }

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
                  reportUndecodablePhoto(image, error, stackTrace);
                  return placeholder;
                },
              ),
      ),
    );
  }
}
