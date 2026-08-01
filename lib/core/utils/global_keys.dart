import 'package:flutter/material.dart';

/// Lets code outside the widget tree (e.g. the background call session,
/// which can show a "student joined" notice even while minimized and not
/// on-screen) surface a SnackBar regardless of which screen is active.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
