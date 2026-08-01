import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shown wherever a participant's video tile would normally render.
///
/// This is a real, permanent piece of UI — not a stopgap: any video call
/// app needs a placeholder for when a participant's camera is off, on
/// purpose or otherwise. It's currently doing double duty while
/// VideoView's exact track-binding API is confirmed against the real
/// daily_flutter 0.38.0 source (see the TODO below) — once that's in,
/// this becomes the fallback shown specifically when cameraEnabled is
/// false, rather than always.
class CameraOffPlaceholder extends StatelessWidget {
  const CameraOffPlaceholder({
    super.key,
    required this.displayName,
    this.compact = false,
  });

  final String displayName;
  final bool compact;

  String get _initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 40.0 : 88.0;
    final fontSize = compact ? 16.0 : 32.0;

    return Container(
      color: const Color(0xFF15182B), // dark neutral, not pure black — reads as intentional
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 10),
              Text(
                displayName,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// TODO(video-view): once VideoViewController's real track-binding API is
// confirmed (see conversation notes), reintroduce the actual video feed:
// show CameraOffPlaceholder only when !session.cameraEnabled, and a real
// VideoView(controller: ...) otherwise. Both call sites (daily_call_screen
// .dart, mini_call_bubble.dart) are structured so that's a small, isolated
// swap — this file doesn't need to change.
