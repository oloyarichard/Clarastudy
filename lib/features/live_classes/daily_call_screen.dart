Future<void> _leave() async {
  // Prevent:
  //
  // Main hang-up
  // +
  // Android/system back
  // +
  // bubble hang-up
  //
  // from starting multiple route operations.
  if (_leaving ||
      _minimizing ||
      !mounted) {
    return;
  }

  setState(() {
    _leaving = true;
  });

  // Exit immersive mode while the route is still alive.
  _exitImmersive();

  final session =
      ref.read(
    dailyCallSessionProvider,
  );

  // Detach this screen's renderers from Daily tracks NOW, while the route
  // and its widgets are still alive and able to do it safely.
  _releaseAllTracks();

  // Kick off the native teardown, but DO NOT block the UI on it.
  //
  // The old code awaited session.leave() — native leave + dispose, which
  // can take seconds on a bad connection — and only popped afterwards.
  // The user pressed "end call" and sat looking at a frozen call screen.
  // That is the "hanging up" problem.
  //
  // The provider is idempotent and owns the whole lifecycle, so it is safe
  // to let it finish after this route is gone.
  final teardown = session.leave();

  unawaited(
    teardown.catchError((Object e, StackTrace stackTrace) {
      debugPrint('Daily leave error: $e');
      debugPrint('Daily leave stack trace:\n$stackTrace');
    }),
  );

  if (!mounted) {
    return;
  }

  // Pop immediately — the call is already logically over.
  Navigator.of(context).pop();
}
