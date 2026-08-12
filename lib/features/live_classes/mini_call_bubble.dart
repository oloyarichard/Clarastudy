import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/global_keys.dart';
import '../../providers/daily_call_session_provider.dart';
import 'call_route.dart';
import 'camera_off_placeholder.dart';

/// Floating picture-in-picture bubble for an ongoing call.
///
/// NOTE: this widget is mounted once for the entire app lifetime (see
/// MaterialApp.builder), so its State is NEVER disposed. Any flag it sets
/// must be reset again, and its VideoViewController is reused across many
/// different calls.
class MiniCallBubble extends ConsumerStatefulWidget {
  const MiniCallBubble({super.key});

  @override
  ConsumerState<MiniCallBubble> createState() => _MiniCallBubbleState();
}

class _MiniCallBubbleState extends ConsumerState<MiniCallBubble> {
  Offset _offset = const Offset(16, 100);

  final VideoViewController _videoController = VideoViewController();

  MediaStreamTrack? _lastTrack;

  bool _leaving = false;

  DailyCallSession? _session;

  @override
  void initState() {
    super.initState();

    // ref.read is safe here (unlike ref.watch, which needs build()).
    _session = ref.read(dailyCallSessionProvider)
      ..addTrackReleaseCallback(_releaseTrack);
  }

  @override
  void dispose() {
    _session?.removeTrackReleaseCallback(_releaseTrack);
    _videoController.dispose();
    super.dispose();
  }

  /// Called by the session immediately before the native client is destroyed.
  /// Detaching here is what stops the renderer from holding a track that is
  /// about to be freed underneath it.
  void _releaseTrack() {
    _lastTrack = null;
    try {
      _videoController.setTrack(null);
    } catch (e) {
      debugPrint('Bubble track release failed: $e');
    }
  }

  void _syncVideoTrack(DailyCallSession session) {
    if (_leaving || session.isTearingDown) return;

    final track = session.client?.participants.local.media?.camera.track;

    if (track != _lastTrack) {
      _lastTrack = track;
      _videoController.setTrack(track);
    }
  }

  Future<void> _hangUp(DailyCallSession session) async {
    if (_leaving) return;

    setState(() => _leaving = true);

    try {
      // The provider owns the ONLY Daily leave/dispose operation.
      await session.leave();
    } catch (e) {
      debugPrint('Bubble leave error: $e');
    }

    // CRITICAL: this State is never disposed (the bubble lives in
    // MaterialApp.builder for the app's whole life). Leaving _leaving = true
    // meant that after ONE hang-up from the bubble, the bubble was dead for
    // every future call — it rendered SizedBox.shrink() forever and never
    // synced a track again. Reset it.
    if (mounted) {
      setState(() => _leaving = false);
    } else {
      _leaving = false;
    }
  }

  void _openFullScreen(DailyCallSession session) {
    if (_leaving || session.isTearingDown) return;

    final id = session.liveClassId;
    if (id == null) return;

    // Keep the Daily call alive — this only flips UI state.
    session.maximize();

    rootNavigatorKey.currentState?.push(
      CallScreenRoute(
        liveClassId: id,
        liveClassTitle: session.liveClassTitle ?? 'Live class',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(dailyCallSessionProvider);

    if (!session.hasActiveCall || !session.isMinimized || _leaving) {
      return const SizedBox.shrink();
    }

    _syncVideoTrack(session);

    final showVideo = session.cameraEnabled && _lastTrack != null;
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          if (_leaving) return;

          setState(() {
            final next = _offset + details.delta;
            _offset = Offset(
              next.dx.clamp(0, screenSize.width - 120),
              next.dy.clamp(0, screenSize.height - 160),
            );
          });
        },
        onTap: () => _openFullScreen(session),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 120,
            height: 160,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (session.client != null)
                  showVideo
                      ? VideoView(controller: _videoController)
                      : CameraOffPlaceholder(
                          displayName: session.liveClassTitle ?? 'Call',
                          compact: true,
                        ),

                // ------------------------------------------------------
                // HANG UP
                // ------------------------------------------------------
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _hangUp(session),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.error,
                      child: Icon(
                        Icons.call_end_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                // ------------------------------------------------------
                // MIC OFF INDICATOR
                // ------------------------------------------------------
                if (!session.micEnabled)
                  const Positioned(
                    bottom: 4,
                    left: 4,
                    child: Icon(
                      Icons.mic_off_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
