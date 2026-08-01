import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/daily_call_session_provider.dart';
import 'daily_call_screen.dart';

/// A small draggable floating bubble shown over the rest of the app
/// whenever a call is active but minimized. Tapping it re-opens the
/// full-screen call view (re-attaching to the same, still-running
/// CallClient — no rejoin). This is inserted once, at the app root (see
/// app.dart's MaterialApp.builder), so it floats over every screen.
class MiniCallBubble extends ConsumerStatefulWidget {
  const MiniCallBubble({super.key});
  
  @override
  ConsumerState<MiniCallBubble> createState() => _MiniCallBubbleState();
}

class _MiniCallBubbleState extends ConsumerState<MiniCallBubble> {
  Offset _offset = const Offset(16, 100);
  
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(dailyCallSessionProvider);
    if (!session.hasActiveCall || !session.isMinimized) {
      return const SizedBox.shrink();
    }
    
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
          Navigator.of(context).push(
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
                  VideoView(
                    videoTrack: session.client!.participants
