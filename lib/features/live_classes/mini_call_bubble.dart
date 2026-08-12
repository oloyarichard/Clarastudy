import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/global_keys.dart';
import '../../providers/daily_call_session_provider.dart';
import 'camera_off_placeholder.dart';
import 'daily_call_screen.dart';

/// A small draggable floating bubble shown over the rest of the app
/// whenever a call is active but minimized.
class MiniCallBubble extends ConsumerStatefulWidget {
  const MiniCallBubble({super.key});

  @override
  ConsumerState<MiniCallBubble> createState() => _MiniCallBubbleState();
}

class _MiniCallBubbleState extends ConsumerState<MiniCallBubble> {
  Offset _offset = const Offset(16, 100);
  bool _leaving = false;

  final _videoController = VideoViewController();
  MediaStreamTrack? _lastTrack;

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  void _syncVideoTrack(DailyCallSession session) {
    if (_leaving) return;
    final track = session.client?.participants.local.media?.camera.track;
    if (track != _lastTrack) {
      _lastTrack = track;
      _videoController.setTrack(track);
    }
  }

  Future<void> _handleLeave(DailyCallSession session) async {
    if (mounted) {
      setState(() => _leaving = true);
    }
    await session.leave();
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
          setState(() {
            final next = _offset + details.delta;
            _offset = Offset(
              next.dx.clamp(0, screenSize.width - 120),
              next.dy.clamp(0, screenSize.height - 160),
            );
          });
        },
        onTap: () {
          session.maximize();
          rootNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => DailyCallScreen(
                liveClassId: session.liveClassId!,
                liveClassTitle: session.liveClassTitle ?? 'Live class',
              ),
              fullscreenDialog: true,
            ),
          );
        },
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
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _handleLeave(session),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.error,
                      child: Icon(Icons.call_end_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
                if (!session.micEnabled)
                  const Positioned(
                    bottom: 4,
                    left: 4,
                    child: Icon(Icons.mic_off_rounded, color: Colors.white, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
