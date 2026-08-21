import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/call_permissions.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/daily_call_session_provider.dart';
import '../../providers/live_class_providers.dart';
import 'camera_off_placeholder.dart';

/// Full-screen, in-app Daily.co call for a live class.
///
/// IMPORTANT LIFECYCLE RULES:
///
/// 1. DailyCallSession owns the native Daily CallClient.
/// 2. This screen NEVER calls CallClient.dispose().
/// 3. Minimizing removes only this Flutter route.
/// 4. Minimizing NEVER calls Daily leave().
/// 5. Full-screen hang-up calls DailyCallSession.leave().
/// 6. Hang-up pops the route FIRST, then leaves/cleans up in the background.
/// 7. PopScope must not interpret a minimize pop as a hang-up.
/// 8. Once leaving starts, this screen stops touching Daily tracks.
/// 9. The bubble and this screen use the same DailyCallSession.
class DailyCallScreen extends ConsumerStatefulWidget {
  const DailyCallScreen({
    super.key,
    required this.liveClassId,
    required this.liveClassTitle,
    this.credentials,
  });

  final String liveClassId;
  final String liveClassTitle;
  final DailyCallCredentials? credentials;

  @override
  ConsumerState<DailyCallScreen> createState() =>
      _DailyCallScreenState();
}

class _DailyCallScreenState
    extends ConsumerState<DailyCallScreen> {
  bool _joining = true;
  bool _immersive = true;
  bool _leaving = false;
  bool _starting = false;

  // IMPORTANT:
  // This is separate from _leaving.
  //
  // When true, the route is being popped ONLY because the user
  // pressed minimize. PopScope must NOT call Daily leave().
  bool _minimizing = false;

  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;

  final VideoViewController _videoController =
      VideoViewController();

  MediaStreamTrack? _lastTrack;

  final Map<String, VideoViewController>
      _remoteControllers = {};

  final Map<String, MediaStreamTrack?>
      _remoteLastTracks = {};

  String? _pinnedRemoteId;

  @override
  void initState() {
    super.initState();

    _enterImmersive();

    final session = ref.read(dailyCallSessionProvider);

    session.addTrackReleaseCallback(_releaseAllTracks);

    // IMPORTANT for the bubble -> full screen transition.
    //
    // _joining used to start as `true` unconditionally, and only flipped to
    // false inside a post-frame callback. So re-opening an ALREADY RUNNING
    // call still painted a black screen with a spinner for at least one
    // frame before showing video. That flash was the "delay" when switching
    // out of the bubble.
    //
    // If the call is already live, there is nothing to join — say so now,
    // synchronously, before the first frame is ever built.
    final alreadyLive = session.hasActiveCall &&
        session.liveClassId == widget.liveClassId;

    _joining = !alreadyLive;

    if (alreadyLive) {
      // Attach this screen's renderers to the live tracks straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _leaving || _minimizing) return;
        setState(() {});
      });
      return;
    }

    // Do not initialize Daily while the native Flutter route/view
    // hierarchy is still being created.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (mounted && !_leaving) {
          _ensureJoined();
        }
      },
    );
  }

  /// Invoked by DailyCallSession right before the native client is
  /// destroyed. Every controller must let go of its track here — disposing
  /// the native client while a VideoViewController still points at a track
  /// is a use-after-free, and that is what took the app down on hang-up.
  void _releaseAllTracks() {
    _lastTrack = null;

    try {
      _videoController.setTrack(null);
    } catch (e) {
      debugPrint('Local track release failed: $e');
    }

    for (final entry in _remoteControllers.entries) {
      try {
        entry.value.setTrack(null);
      } catch (e) {
        debugPrint('Remote track release failed: $e');
      }
    }

    _remoteLastTracks.clear();
  }

  @override
  void dispose() {
    // IMPORTANT:
    //
    // The Daily CallClient belongs to DailyCallSession.
    //
    // We only dispose VideoView controllers owned by this screen.
    // We NEVER call:
    //
    // ref.read(dailyCallSessionProvider).client?.dispose()
    //
    // from here.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    // Stop the session from calling back into a dead State.
    ref
        .read(dailyCallSessionProvider)
        .removeTrackReleaseCallback(_releaseAllTracks);

    // Detach before destroying, always in that order.
    _releaseAllTracks();

    _videoController.dispose();

    for (final controller
        in _remoteControllers.values) {
      controller.dispose();
    }

    _remoteControllers.clear();
    _remoteLastTracks.clear();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SYSTEM UI
  // ---------------------------------------------------------------------------

  void _enterImmersive() {
    if (!mounted || _leaving) {
      return;
    }

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  void _toggleFullscreen() {
    if (_leaving || _minimizing) {
      return;
    }

    setState(() {
      _immersive = !_immersive;
    });

    if (_immersive) {
      _enterImmersive();
    } else {
      _exitImmersive();
    }
  }

  // ---------------------------------------------------------------------------
  // JOIN
  // ---------------------------------------------------------------------------

  Future<void> _ensureJoined() async {
    if (_starting ||
        _leaving ||
        _minimizing ||
        !mounted) {
      return;
    }

    _starting = true;

    try {
      final session =
          ref.read(dailyCallSessionProvider);

      // If the call is already active, this screen only needs
      // to display it.
      //
      // DO NOT create another CallClient.
      if (session.hasActiveCall &&
          session.liveClassId ==
              widget.liveClassId) {
        if (mounted && !_leaving) {
          setState(() {
            _joining = false;
          });
        }

        return;
      }

      if (widget.credentials == null) {
        if (mounted && !_leaving) {
          setState(() {
            _joining = false;
            _errorMessage =
                'No active call to show.';
          });
        }

        return;
      }

      final user =
          ref.read(authProvider).user;

      await session.start(
        liveClassId:
            widget.liveClassId,
        liveClassTitle:
            widget.liveClassTitle,
        credentials:
            widget.credentials!,
        currentUserId: user?.id,
      );

      if (mounted && !_leaving) {
        setState(() {
          _joining = false;
        });
      }
    } on CallPermissionException catch (e) {
      // This is the crash the app used to have: Daily's SDK does not ask
      // for camera/mic permission itself, so creating a CallClient without
      // it previously took the whole app down instead of surfacing here.
      if (mounted && !_leaving) {
        setState(() {
          _joining = false;
          _errorMessage = e.message;
          _permissionPermanentlyDenied = e.permanentlyDenied;
        });
      }
    } catch (e, stackTrace) {
      debugPrint(
        'Daily start error: $e',
      );

      debugPrint(
        'Daily start stack trace:\n$stackTrace',
      );

      if (mounted && !_leaving) {
        setState(() {
          _joining = false;
          _errorMessage =
              'Could not join the call. Check your connection and try again.';
          _permissionPermanentlyDenied = false;
        });
      }
    } finally {
      _starting = false;
    }
  }

  // ---------------------------------------------------------------------------
  // LEAVE
  // ---------------------------------------------------------------------------

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

    if (!mounted) {
      return;
    }

    // Take the user back to the previous screen FIRST. Every bit of Daily
    // cleanup — detaching tracks, leaving the room, disposing the native
    // client — happens AFTER this pop, once the call screen and its video
    // surface are already on their way out.
    //
    // Doing that cleanup BEFORE the pop meant the native call teardown
    // could start while this screen's video surface was still fully
    // mounted and actively rendering — exactly the kind of timing that
    // crashes native video SDKs. Popping first means Flutter's own widget
    // disposal (which detaches this screen's VideoViewControllers via
    // dispose()) is already underway before anything touches the native
    // client.
    Navigator.of(context).pop();

    // Still synchronous up to here — nothing above this line blocked on
    // an await, so the navigation above is not delayed by any of this.
    final teardown = session.leave();

    unawaited(
      teardown.catchError((Object e, StackTrace stackTrace) {
        debugPrint('Daily leave error: $e');
        debugPrint('Daily leave stack trace:\n$stackTrace');
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // MINIMIZE
  // ---------------------------------------------------------------------------

  void _minimize() {
    if (_leaving ||
        _minimizing ||
        !mounted) {
      return;
    }

    final session =
        ref.read(
      dailyCallSessionProvider,
    );

    if (!session.hasActiveCall) {
      return;
    }

    // Tell PopScope that the next pop is intentional
    // and represents MINIMIZE, not LEAVE.
    setState(() {
      _minimizing = true;
    });

    // This ONLY changes provider UI state.
    //
    // It MUST NOT leave the Daily room.
    session.minimize();

    // Remove the full-screen route.
    //
    // The Daily CallClient stays alive inside
    // DailyCallSession.
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // CAMERA
  // ---------------------------------------------------------------------------

  Future<void> _flipCamera() async {
    if (_leaving ||
        _minimizing ||
        !mounted) {
      return;
    }

    try {
      await ref
          .read(
            dailyCallSessionProvider,
          )
          .flipCamera();
    } catch (e, stackTrace) {
      debugPrint(
        'Flip camera error: $e',
      );

      debugPrint(
        'Flip camera stack trace:\n$stackTrace',
      );

      if (mounted && !_leaving) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Could not switch camera: $e',
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // VIDEO TRACKS
  // ---------------------------------------------------------------------------

  void _syncVideoTrack(
    DailyCallSession session,
  ) {
    // Deliberately NOT guarded by _minimizing: video must keep updating
    // through the minimize fade, or the frozen last frame is what read as
    // "visual delay" when switching to the bubble.
    if (_leaving ||
        session.isTearingDown ||
        !mounted) {
      return;
    }

    final track = session
        .client
        ?.participants
        .local
        .media
        ?.camera
        .track;

    if (track != _lastTrack) {
      _lastTrack = track;

      if (!_leaving) {
        _videoController.setTrack(
          track,
        );
      }
    }
  }
  void _syncRemoteControllers(
    DailyCallSession session,
  ) {
    // Same reasoning as _syncVideoTrack: keep syncing through the minimize
    // fade.
    if (_leaving ||
        session.isTearingDown ||
        !mounted) {
      return;
    }

    final remote =
        session.client
                ?.participants
                .remote ??
            {};

    final currentIds = remote.keys
        .map(
          (id) => id.id,
        )
        .toSet();

    // Remove controllers for participants
    // who are no longer present.
    final staleIds =
        _remoteControllers.keys
            .where(
              (id) =>
                  !currentIds.contains(id),
            )
            .toList();

    for (final id in staleIds) {
      if (_leaving || !mounted) {
        return;
      }

      final controller =
          _remoteControllers.remove(
        id,
      );

      _remoteLastTracks.remove(id);

      // Dispose only this screen's controller.
      controller?.dispose();
    }

    // Create/update controllers for active
    // remote participants.
    for (final entry
        in remote.entries) {
      if (_leaving || !mounted) {
        return;
      }

      final id = entry.key.id;

      final track =
          entry.value.media?.camera.track;

      final controller =
          _remoteControllers.putIfAbsent(
        id,
        () => VideoViewController(),
      );

      if (_remoteLastTracks[id] !=
          track) {
        _remoteLastTracks[id] = track;

        if (!_leaving && mounted) {
          controller.setTrack(track);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // MAIN PARTICIPANT
  // ---------------------------------------------------------------------------

  MapEntry<String, Participant>?
      _mainRemoteParticipant(
    DailyCallSession session,
  ) {
    if (_leaving) {
      return null;
    }

    final remote =
        session.client
                ?.participants
                .remote ??
            {};

    if (remote.isEmpty) {
      return null;
    }

    if (_pinnedRemoteId != null) {
      final pinned =
          remote.entries.where(
        (entry) =>
            entry.key.id ==
            _pinnedRemoteId,
      );

      if (pinned.isNotEmpty) {
        return MapEntry(
          pinned.first.key.id,
          pinned.first.value,
        );
      }

      _pinnedRemoteId = null;
    }

    // Students see the moderator by default.
    if (!session.isOwner) {
      final moderator =
          remote.entries.where(
        (entry) =>
            entry.value.info.isOwner,
      );

      if (moderator.isNotEmpty) {
        return MapEntry(
          moderator.first.key.id,
          moderator.first.value,
        );
      }
    }

    // Teacher's own video remains default.
    return null;
  }

  // ---------------------------------------------------------------------------
  // LOCAL VIDEO
  // ---------------------------------------------------------------------------

  Widget _localVideoTile(
    DailyCallSession session, {
    bool compact = false,
  }) {
    // Only a real teardown blanks the tile. Minimizing keeps rendering so
    // the fade to the bubble stays continuous instead of flashing black.
    if (_leaving) {
      return const ColoredBox(
        color: Colors.black,
      );
    }

    final showVideo =
        session.cameraEnabled &&
        _lastTrack != null;

    if (showVideo) {
      return VideoView(
        controller:
            _videoController,
      );
    }

    return CameraOffPlaceholder(
      displayName:
          ref
                  .watch(
                    authProvider,
                  )
                  .user
                  ?.displayName ??
              'You',
      compact: compact,
    );
  }

  // ---------------------------------------------------------------------------
  // REMOTE VIDEO
  // ---------------------------------------------------------------------------

  Widget _remoteVideoTile(
    String id,
    Participant participant, {
    bool compact = false,
  }) {
    if (_leaving) {
      return const ColoredBox(
        color: Colors.black,
      );
    }

    final controller =
        _remoteControllers[id];

    final showVideo =
        !participant.isCameraMuted &&
        controller != null;

    if (showVideo) {
      return VideoView(
        controller: controller,
      );
    }

    return CameraOffPlaceholder(
      displayName:
          participant
                      .info
                      .username
                      ?.isNotEmpty ??
                  false
              ? participant
                  .info
                  .username!
              : 'Participant',
      compact: compact,
    );
  }

  // ---------------------------------------------------------------------------
  // THUMBNAILS
  // ---------------------------------------------------------------------------

  Widget _thumbnailStrip(
    DailyCallSession session,
    String? mainRemoteId,
  ) {
    if (_leaving) {
      return const SizedBox.shrink();
    }

    final remote =
        session.client
                ?.participants
                .remote ??
            {};

    final others =
        remote.entries
            .where(
              (entry) =>
                  entry.key.id !=
                  mainRemoteId,
            )
            .toList();

    final showLocalTile =
        mainRemoteId != null;

    if (others.isEmpty &&
        !showLocalTile) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection:
            Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
        ),
        children: [
          if (showLocalTile)
            _thumbnailTile(
              child:
                  _localVideoTile(
                session,
                compact: true,
              ),
              muted:
                  !session.micEnabled,
              onTap: () {
                if (!_leaving &&
                    !_minimizing &&
                    mounted) {
                  setState(() {
                    _pinnedRemoteId =
                        null;
                  });
                }
              },
            ),
          ...others.map(
            (entry) =>
                _thumbnailTile(
              child:
                  _remoteVideoTile(
                entry.key.id,
                entry.value,
                compact: true,
              ),
              muted: entry.value
                  .isMicrophoneMuted,
              onTap: () {
                if (!_leaving &&
                    !_minimizing &&
                    mounted) {
                  setState(() {
                    _pinnedRemoteId =
                        entry.key.id;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailTile({
    required Widget child,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(
        right: 10,
      ),
      child: GestureDetector(
        onTap:
            _leaving ||
                    _minimizing
                ? null
                : onTap,
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          child: SizedBox(
            width: 68,
            height: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.black,
                  child: child,
                ),
                if (muted)
                  const Positioned(
                    bottom: 4,
                    left: 4,
                    child: Icon(
                      Icons
                          .mic_off_rounded,
                      color:
                          Colors.white,
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

  // ---------------------------------------------------------------------------
  // CHAT
  // ---------------------------------------------------------------------------

  void _openAppChat() {
    if (_leaving ||
        _minimizing ||
        !mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent,
      builder: (_) =>
          _LiveClassChatSheet(
        liveClassId:
            widget.liveClassId,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PARTICIPANTS
  // ---------------------------------------------------------------------------

  void _openParticipants() {
    if (_leaving ||
        _minimizing ||
        !mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor:
          AppColors.cardLight,
      builder: (_) => Consumer(
        builder:
            (context, ref, __) {
          final session =
              ref.watch(
            dailyCallSessionProvider,
          );

          return ListView(
            shrinkWrap: true,
            padding:
                const EdgeInsets.all(
              16,
            ),
            children: [
              Padding(
                padding:
                    const EdgeInsets.only(
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Participants',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (session.isOwner &&
                        session
                            .participants
                            .isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          if (!_leaving &&
                              !_minimizing) {
                            session
                                .toggleMuteAll();
                          }
                        },
                        icon: Icon(
                          session.allMuted
                              ? Icons
                                  .mic_rounded
                              : Icons
                                  .mic_off_rounded,
                          size: 18,
                        ),
                        label: Text(
                          session.allMuted
                              ? 'Unmute all'
                              : 'Mute all',
                        ),
                      ),
                  ],
                ),
              ),
              ...session
                  .participants
                  .entries
                  .map(
                (entry) => ListTile(
                  leading:
                      const Icon(
                    Icons
                        .person_rounded,
                  ),
                  title:
                      Text(entry.value),
                  trailing:
                      session.isOwner
                          ? IconButton(
                              icon:
                                  const Icon(
                                Icons
                                    .mic_off_rounded,
                              ),
                              tooltip:
                                  'Mute',
                              onPressed:
                                  _leaving ||
                                          _minimizing
                                      ? null
                                      : () =>
                                          session
                                              .muteParticipant(
                                            entry.key,
                                          ),
                            )
                          : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(
    BuildContext context,
  ) {
    final session =
        ref.watch(
      dailyCallSessionProvider,
    );

    return PopScope(
      // Never let Flutter automatically pop this route.
      //
      // We explicitly pop after Daily cleanup for a real hang-up.
      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) {
        // IMPORTANT:
        //
        // _minimizing means this pop was intentionally
        // caused by the minimize button.
        //
        // Therefore NEVER call Daily leave here.
        if (_minimizing) {
          return;
        }

        if (didPop ||
            _leaving) {
          return;
        }

        _leave();
      },

      child: Scaffold(
        backgroundColor:
            Colors.black,

        body: SafeArea(
          child: _joining
              ? Stack(
                  children: [
                    const Center(
                      child:
                          CircularProgressIndicator(
                        color:
                            Colors.white,
                      ),
                    ),

                    Positioned(
                      top: 8,
                      left: 8,
                      child:
                          TextButton.icon(
                        onPressed:
                            _leaving
                                ? null
                                : _leave,
                        style:
                            TextButton
                                .styleFrom(
                          foregroundColor:
                              Colors.white70,
                        ),
                        icon:
                            const Icon(
                          Icons
                              .arrow_back_rounded,
                          size: 18,
                        ),
                        label:
                            const Text(
                          'Cancel',
                        ),
                      ),
                    ),
                  ],
                )
              : _errorMessage != null
                  ? Center(
                      child:
                          Padding(
                        padding:
                            const EdgeInsets
                                .all(
                          24,
                        ),
                        child:
                            Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: [
                            Icon(
                              _permissionPermanentlyDenied
                                  ? Icons
                                      .videocam_off_rounded
                                  : Icons
                                      .wifi_off_rounded,
                              color:
                                  Colors.white54,
                              size: 48,
                            ),

                            const SizedBox(
                              height: 16,
                            ),

                            Text(
                              _errorMessage!,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.white,
                              ),
                              textAlign:
                                  TextAlign
                                      .center,
                            ),

                            const SizedBox(
                              height: 24,
                            ),

                            Row(
                              mainAxisSize:
                                  MainAxisSize
                                      .min,
                              children: [
                                OutlinedButton(
                                  onPressed:
                                      _leave,
                                  style:
                                      OutlinedButton
                                          .styleFrom(
                                    foregroundColor:
                                        Colors.white,
                                    side:
                                        const BorderSide(
                                      color:
                                          Colors.white54,
                                    ),
                                  ),
                                  child:
                                      const Text(
                                    'Close',
                                  ),
                                ),

                                const SizedBox(
                                  width: 12,
                                ),

                                FilledButton(
                                  onPressed:
                                      _starting ||
                                              _leaving
                                          ? null
                                          : _permissionPermanentlyDenied
                                              ? () => CallPermissions
                                                  .openSettings()
                                              : () {
                                                  setState(
                                                    () {
                                                      _errorMessage =
                                                          null;
                                                      _joining =
                                                          true;
                                                    },
                                                  );

                                                  WidgetsBinding
                                                      .instance
                                                      .addPostFrameCallback(
                                                    (_) {
                                                      if (mounted &&
                                                          !_leaving) {
                                                        _ensureJoined();
                                                      }
                                                    },
                                                  );
                                                },
                                  child: Text(
                                    _permissionPermanentlyDenied
                                        ? 'Open settings'
                                        : 'Try again',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : _leaving
                      ? const ColoredBox(
                          color:
                              Colors.black,
                        )
                      : Builder(
                          builder:
                              (context) {
                            if (!_leaving) {
                              _syncVideoTrack(
                                session,
                              );

                              _syncRemoteControllers(
                                session,
                              );
                            }

                            final mainRemote =
                                _mainRemoteParticipant(
                              session,
                            );

                            return Stack(
                              children: [
                                // ------------------------------------------------
                                // MAIN VIDEO
                                // ------------------------------------------------

                                if (!_leaving &&
                                    session.client !=
                                        null)
                                  Positioned.fill(
                                    child:
                                        mainRemote !=
                                                null
                                            ? _remoteVideoTile(
                                                mainRemote.key,
                                                mainRemote.value,
                                              )
                                            : _localVideoTile(
                                                session,
                                              ),
                                  ),

                                // ------------------------------------------------
                                // MICROPHONE STATUS
                                // ------------------------------------------------

                                if (!_leaving &&
                                    session.client !=
                                        null)
                                  Positioned(
                                    left: 16,
                                    bottom: 112,
                                    child: Row(
                                      mainAxisSize:
                                          MainAxisSize.min,
                                      children: [
                                        if (mainRemote
                                                ?.value
                                                .isMicrophoneMuted ??
                                            !session
                                                .micEnabled)
                                          Container(
                                            padding:
                                                const EdgeInsets.all(
                                              6,
                                            ),
                                            decoration:
                                                const BoxDecoration(
                                              color:
                                                  Colors.black45,
                                              shape:
                                                  BoxShape.circle,
                                            ),
                                            child:
                                                const Icon(
                                              Icons
                                                  .mic_off_rounded,
                                              color:
                                                  Colors.white,
                                              size:
                                                  16,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                // ------------------------------------------------
                                // THUMBNAILS
                                // ------------------------------------------------

                                if (!_leaving &&
                                    session.client !=
                                        null)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 96,
                                    child:
                                        _thumbnailStrip(
                                      session,
                                      mainRemote
                                          ?.key,
                                    ),
                                  ),

                                // ------------------------------------------------
                                // TOP BAR
                                // ------------------------------------------------

                                Positioned(
                                  top: 12,
                                  left: 16,
                                  right: 16,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon:
                                            const Icon(
                                          Icons
                                              .keyboard_arrow_down_rounded,
                                          color:
                                              Colors.white,
                                        ),
                                        tooltip:
                                            'Minimize',
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : _minimize,
                                      ),

                                      Expanded(
                                        child:
                                            Text(
                                          widget
                                              .liveClassTitle,
                                          style:
                                              const TextStyle(
                                            color:
                                                Colors.white,
                                            fontWeight:
                                                FontWeight.w700,
                                          ),
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                        ),
                                      ),

                                      IconButton(
                                        icon:
                                            Icon(
                                          _immersive
                                              ? Icons
                                                  .fullscreen_exit_rounded
                                              : Icons
                                                  .fullscreen_rounded,
                                          color:
                                              Colors.white,
                                        ),
                                        tooltip:
                                            _immersive
                                                ? 'Exit fullscreen'
                                                : 'Fullscreen',
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : _toggleFullscreen,
                                      ),

                                      if (session
                                          .isOwner)
                                        IconButton(
                                          icon:
                                              const Icon(
                                            Icons
                                                .people_alt_rounded,
                                            color:
                                                Colors.white,
                                          ),
                                          onPressed:
                                              _leaving ||
                                                      _minimizing
                                                  ? null
                                                  : _openParticipants,
                                        ),
                                    ],
                                  ),
                                ),

                                // ------------------------------------------------
                                // RAISED HANDS
                                // ------------------------------------------------

                                if (!_leaving &&
                                    session
                                        .raisedHands
                                        .isNotEmpty)
                                  Positioned(
                                    top: 56,
                                    left: 16,
                                    right: 16,
                                    child:
                                        Wrap(
                                      spacing: 6,
                                      runSpacing:
                                          6,
                                      children:
                                          session
                                              .raisedHands
                                              .map(
                                        (entry) =>
                                            Chip(
                                          backgroundColor:
                                              AppColors.accent,
                                          label:
                                              Text(
                                            entry.userName,
                                            style:
                                                const TextStyle(
                                              color:
                                                  Colors.white,
                                              fontSize:
                                                  12,
                                            ),
                                          ),
                                          avatar:
                                              const Icon(
                                            Icons
                                                .back_hand_rounded,
                                            color:
                                                Colors.white,
                                            size:
                                                16,
                                          ),
                                          onDeleted:
                                              session.isOwner &&
                                                      !_leaving &&
                                                      !_minimizing
                                                  ? () =>
                                                      session.lowerHand(
                                                        entry.userId,
                                                      )
                                                  : null,
                                          deleteIcon:
                                              session.isOwner
                                                  ? const Icon(
                                                      Icons
                                                          .close_rounded,
                                                      color:
                                                          Colors.white,
                                                      size:
                                                          16,
                                                    )
                                                  : null,
                                        ),
                                      )
                                              .toList(),
                                    ),
                                  ),

                                // ------------------------------------------------
                                // CHAT
                                // ------------------------------------------------

                                Positioned(
                                  right: 16,
                                  bottom: 100,
                                  child:
                                      FloatingActionButton(
                                    heroTag:
                                        'live-class-chat-fab',
                                    backgroundColor:
                                        AppColors.primary,
                                    onPressed:
                                        _leaving ||
                                                _minimizing
                                            ? null
                                            : _openAppChat,
                                    child:
                                        const Icon(
                                      Icons
                                          .chat_bubble_rounded,
                                      color:
                                          Colors.white,
                                    ),
                                  ),
                                ),
                                // ------------------------------------------------
                                // BOTTOM CONTROLS
                                // ------------------------------------------------

                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 24,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .center,
                                    children: [
                                      _CallControlButton(
                                        icon: session
                                                .micEnabled
                                            ? Icons
                                                .mic_rounded
                                            : Icons
                                                .mic_off_rounded,
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : () =>
                                                    session.toggleMic(),
                                      ),

                                      const SizedBox(
                                        width: 16,
                                      ),

                                      _CallControlButton(
                                        icon: session
                                                .cameraEnabled
                                            ? Icons
                                                .videocam_rounded
                                            : Icons
                                                .videocam_off_rounded,
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : () =>
                                                    session.toggleCamera(),
                                      ),

                                      const SizedBox(
                                        width: 16,
                                      ),

                                      _CallControlButton(
                                        icon: Icons
                                            .cameraswitch_rounded,
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : _flipCamera,
                                      ),

                                      const SizedBox(
                                        width: 16,
                                      ),

                                      // ------------------------------------------------
                                      // HANG UP
                                      // ------------------------------------------------

                                      _CallControlButton(
                                        icon: Icons
                                            .call_end_rounded,
                                        color:
                                            AppColors.error,
                                        onPressed:
                                            _leaving ||
                                                    _minimizing
                                                ? null
                                                : _leave,
                                      ),

                                      if (!session
                                          .isOwner) ...[
                                        const SizedBox(
                                          width: 16,
                                        ),

                                        _CallControlButton(
                                          icon: Icons
                                              .back_hand_rounded,
                                          color: session
                                                  .myHandRaised
                                              ? AppColors
                                                  .accent
                                              : null,
                                          onPressed:
                                              _leaving ||
                                                      _minimizing
                                                  ? null
                                                  : () =>
                                                      session.toggleMyHand(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CALL CONTROL BUTTON
// -----------------------------------------------------------------------------

class _CallControlButton
    extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(
    BuildContext context,
  ) {
    return CircleAvatar(
      radius: 28,
      backgroundColor:
          color ?? Colors.white24,
      child: IconButton(
        icon: Icon(
          icon,
          color: Colors.white,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REST-BACKED LIVE CLASS CHAT
// -----------------------------------------------------------------------------

class _LiveClassChatSheet
    extends ConsumerStatefulWidget {
  const _LiveClassChatSheet({
    required this.liveClassId,
  });

  final String liveClassId;

  @override
  ConsumerState<
      _LiveClassChatSheet> createState() =>
      _LiveClassChatSheetState();
}

class _LiveClassChatSheetState
    extends ConsumerState<
        _LiveClassChatSheet> {
  final _controller =
      TextEditingController();

  bool _sending = false;

  Timer? _pollTimer;

  ScrollController?
      _chatScrollController;

  int _lastMessageCount = 0;

  void _scrollToBottom() {
    final controller =
        _chatScrollController;

    if (controller == null ||
        !controller.hasClients) {
      return;
    }

    controller.animateTo(
      controller.position
          .maxScrollExtent,
      duration:
          const Duration(
        milliseconds: 250,
      ),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();

    _pollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          ref.invalidate(
            liveChatProvider(
              widget.liveClassId,
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;

    _controller.dispose();

    super.dispose();
  }

  Future<void> _send() async {
    final text =
        _controller.text.trim();

    if (text.isEmpty ||
        _sending ||
        !mounted) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await ref
          .read(
            liveClassRepositoryProvider,
          )
          .sendLiveChat(
            liveClassId:
                widget.liveClassId,
            message: text,
          );

      if (!mounted) {
        return;
      }

      _controller.clear();

      ref.invalidate(
        liveChatProvider(
          widget.liveClassId,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              'Could not send message: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final chatAsync =
        ref.watch(
      liveChatProvider(
        widget.liveClassId,
      ),
    );

    final user =
        ref.watch(authProvider).user;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder:
          (
        context,
        scrollController,
      ) {
        _chatScrollController =
            scrollController;

        return Padding(
          padding:
              EdgeInsets.only(
            bottom: MediaQuery.of(
              context,
            ).viewInsets.bottom,
          ),
          child: Container(
            decoration:
                const BoxDecoration(
              color:
                  AppColors.cardLight,
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(
                  20,
                ),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(
                  height: 10,
                ),

                Container(
                  width: 40,
                  height: 4,
                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.border,
                    borderRadius:
                        BorderRadius.circular(
                      2,
                    ),
                  ),
                ),

                const Padding(
                  padding:
                      EdgeInsets.all(12),
                  child: Text(
                    'Class chat',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),

                Expanded(
                  child: chatAsync.when(
                    data: (messages) {
                      if (messages.length >
                          _lastMessageCount) {
                        _lastMessageCount =
                            messages.length;

                        WidgetsBinding
                            .instance
                            .addPostFrameCallback(
                          (_) =>
                              _scrollToBottom(),
                        );
                      }

                      return ListView
                          .builder(
                        controller:
                            scrollController,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 16,
                        ),
                        itemCount:
                            messages.length,
                        itemBuilder:
                            (
                          context,
                          index,
                        ) {
                          final msg =
                              messages[index];

                          final isMine =
                              msg.userId ==
                                  user?.id;

                          return Align(
                            alignment:
                                isMine
                                    ? Alignment
                                        .centerRight
                                    : Alignment
                                        .centerLeft,
                            child:
                                Container(
                              margin:
                                  const EdgeInsets
                                      .only(
                                bottom: 8,
                              ),
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration:
                                  BoxDecoration(
                                color: isMine
                                    ? AppColors
                                        .primary
                                    : AppColors
                                        .surfaceLight,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  14,
                                ),
                              ),
                              child: Text(
                                msg.message,
                                style:
                                    TextStyle(
                                  color: isMine
                                      ? Colors
                                          .white
                                      : AppColors
                                          .textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(
                      child:
                          CircularProgressIndicator(),
                    ),
                    error: (
                      e,
                      __,
                    ) =>
                        Center(
                      child: Text(
                        '$e',
                      ),
                    ),
                  ),
                ),

                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child:
                              TextField(
                            controller:
                                _controller,
                            decoration:
                                const InputDecoration(
                              hintText:
                                  'Message the class...',
                            ),
                            onSubmitted:
                                (_) =>
                                    _send(),
                          ),
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        IconButton.filled(
                          onPressed:
                              _sending
                                  ? null
                                  : _send,
                          icon:
                              const Icon(
                            Icons
                                .send_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
