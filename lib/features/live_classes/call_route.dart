import 'package:flutter/material.dart';

import '../../models/live_class_models.dart';
import 'daily_call_screen.dart';

/// A near-instant route for the call screen.
///
/// The default MaterialPageRoute runs a ~300ms slide-up plus a matching
/// reverse on pop. Between the bubble and full screen that transition is
/// pure dead time — the call is already running and there is nothing to
/// load, so the animation IS most of the "delay" when switching. A short
/// cross fade reads as immediate without being a hard cut.
class CallScreenRoute extends PageRouteBuilder<void> {
  CallScreenRoute({
    required this.liveClassId,
    required this.liveClassTitle,
    this.credentials,
  }) : super(
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 140),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (_, __, ___) => DailyCallScreen(
            liveClassId: liveClassId,
            liveClassTitle: liveClassTitle,
            credentials: credentials,
          ),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        );

  final String liveClassId;
  final String liveClassTitle;
  final DailyCallCredentials? credentials;
}
