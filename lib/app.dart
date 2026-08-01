import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_constants.dart';
import 'core/utils/global_keys.dart';
import 'features/live_classes/mini_call_bubble.dart';

class EdutechApp extends ConsumerWidget {
  const EdutechApp({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
              const MiniCallBubble(),
          ],
        );
      },
    );
  }
}
