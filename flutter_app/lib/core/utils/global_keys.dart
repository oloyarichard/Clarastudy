import 'package:flutter/material.dart';

/// Lets code outside the widget tree (e.g. the background call session,
/// which can show a "student joined" notice even while minimized and not
/// on-screen) surface a SnackBar regardless of which screen is active.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The router's navigator. MiniCallBubble is mounted above GoRouter's
/// own navigator (via MaterialApp.builder), so Navigator.of(context)
/// from inside it doesn't reliably resolve to the routed navigator —
/// using this key directly does.
final rootNavigatorKey = GlobalKey<NavigatorState>();
