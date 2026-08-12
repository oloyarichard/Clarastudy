import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/daily_call_session_provider.dart';
import '../../providers/live_class_providers.dart';
import 'camera_off_placeholder.dart';

/// Full-screen, in-app Daily.co call for a live class.
///
/// The CallClient lives inside DailyCallSession so minimizing this screen
/// does not terminate the call. Re-opening the screen attaches to the
/// existing session.
///
/// Important lifecycle rules:
/// 1. Daily startup happens after the first Flutter frame.
/// 2. Only one startup operation can run at a time.
/// 3. Leaving waits for Daily to finish before popping the route.
/// 4. Android/system back uses the same leave path.
/// 5. Once leaving starts, this screen stops touching Daily controllers.
/// 6. This screen NEVER directly disposes the Daily CallClient.
/// 7. The DailyCallSession owns the native Daily lifecycle.
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

  String? _errorMessage;

  final _videoController = VideoViewController();

  MediaStreamTrack? _lastTrack;

  final Map<String, VideoViewController> _remoteControllers =
      {};

  final Map<String, MediaStreamTrack?> _remoteLastTracks =
      {};

  String? _pinnedRemoteId;

  @override
  void initState() {
    super.initState();

    _enterImmersive();

    // Do not initialize Daily while the native Flutter route/view
    // hierarchy is still being created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_leaving) {
        _ensureJoined();
      }
    });
  }

  @override
  void dispose() {
    // IMPORTANT:
    // The Daily CallClient belongs to DailyCallSession.
    //
    // We only dispose the VideoView controllers owned by this screen.
    // The provider has already completed Daily leave() before this route
    // is normally popped.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    _videoController.dispose();

    for (final controller in _remoteControllers.values) {
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
    if (_leaving) {
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
    if (_starting || _leaving || !mounted) {
      return;
    }

    _starting = true;

    try {
      final session =
          ref.read(dailyCallSessionProvider);

      // If the call is already active, this screen only needs to
      // display it. Do NOT create another CallClient.
      if (session.hasActiveCall &&
          session.liveClassId == widget.liveClassId) {
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
        liveClassId: widget.liveClassId,
        liveClassTitle: widget.liveClassTitle,
        credentials: widget.credentials!,
        currentUserId: user?.id,
      );

      if (mounted && !_leaving) {
        setState(() {
          _joining = false;
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
              'Could not join the call: $e';
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
    // This prevents:
    //
    // Main hang-up button
    //        +
    // Android back
    //        +
    // bubble hang-up
    //
    // from starting multiple route teardown operations.
    if (_leaving) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _leaving = true;
    });

    // Make sure immersive mode is removed while the route is still alive.
    _exitImmersive();

    final session =
        ref.read(dailyCallSessionProvider);

    try {
      // IMPORTANT:
      //
      // Do NOT dispose the Daily client here.
      //
      // DailyCallSession owns:
      //   leave()
      //   dispose()
      //   event subscriptions
      //   timers
      //   CallClient
      //
      // We wait until the provider has completely finished its native
      // teardown BEFORE popping this route.
      await session.leave();
    } catch (e, stackTrace) {
      debugPrint(
        'Daily leave error: $e',
      );

      debugPrint(
        'Daily leave stack trace:\n$stackTrace',
      );
    }

    if (!mounted) {
      return;
    }

    // Only now remove the Flutter route.
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // MINIMIZE
  // ---------------------------------------------------------------------------

  void _minimize() {
    if (_leaving || !mounted) {
      return;
    }

    final session =
        ref.read(dailyCallSessionProvider);

    if (!session.hasActiveCall) {
      return;
    }

    session.minimize();

    // IMPORTANT:
    // This only removes the full-screen route.
    //
    // It does NOT call Daily leave().
    //
    // The CallClient remains alive inside DailyCallSession.
    Navigator.of(context).maybePop();
  }

  // ---------------------------------------------------------------------------
  // CAMERA
  // ---------------------------------------------------------------------------

  Future<void> _flipCamera() async {
    if (_leaving || !mounted) {
      return;
    }

    try {
      await ref
          .read(dailyCallSessionProvider)
          .flipCamera();
    } catch (e, stackTrace) {
      debugPrint(
        'Flip camera error: $e',
      );

      debugPrint(
        'Flip camera stack trace:\n$stackTrace',
      );

      if (mounted && !_leaving) {
        ScaffoldMessenger.of(context).showSnackBar(
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
    if (_leaving) {
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

      // Do not update the controller after the screen starts leaving.
      if (!_leaving) {
        _videoController.setTrack(track);
      }
    }
  }

  void _syncRemoteControllers(
    DailyCallSession session,
  ) {
    if (_leaving) {
      return;
    }

    final remote =
        session.client?.participants.remote ?? {};

    final currentIds = remote.keys
        .map((id) => id.id)
        .toSet();

    // Remove controllers belonging to participants who have left.
    final staleIds = _remoteControllers.keys
        .where(
          (id) => !currentIds.contains(id),
        )
        .toList();

    for (final id in staleIds) {
      final controller =
          _remoteControllers.remove(id);

      _remoteLastTracks.remove(id);

      controller?.dispose();
    }

    // Create/update controllers for active remote participants.
    for (final entry in remote.entries) {
      if (_leaving) {
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

      if (_remoteLastTracks[id] != track) {
        _remoteLastTracks[id] = track;

        if (!_leaving) {
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
        session.client?.participants.remote ?? {};

    if (remote.isEmpty) {
      return null;
    }

    if (_pinnedRemoteId != null) {
      final pinned = remote.entries.where(
        (entry) =>
            entry.key.id == _pinnedRemoteId,
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
      final moderator = remote.entries.where(
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

    // Teacher's own video remains the default.
    return null;
  }

  // ---------------------------------------------------------------------------
  // LOCAL VIDEO
  // ---------------------------------------------------------------------------

  Widget _localVideoTile(
    DailyCallSession session, {
    bool compact = false,
  }) {
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
        controller: _videoController,
      );
    }

    return CameraOffPlaceholder(
      displayName:
          ref.watch(authProvider).user?.displayName ??
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
          participant.info.username?.isNotEmpty ??
                  false
              ? participant.info.username!
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
        session.client?.participants.remote ?? {};

    final others = remote.entries
        .where(
          (entry) =>
              entry.key.id != mainRemoteId,
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
              child: _localVideoTile(
                session,
                compact: true,
              ),
              muted: !session.micEnabled,
              onTap: () {
                if (!_leaving && mounted) {
                  setState(() {
                    _pinnedRemoteId = null;
                  });
                }
              },
            ),
          ...others.map(
            (entry) => _thumbnailTile(
              child: _remoteVideoTile(
                entry.key.id,
                entry.value,
                compact: true,
              ),
              muted:
                  entry.value.isMicrophoneMuted,
              onTap: () {
                if (!_leaving && mounted) {
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
          const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap:
            _leaving ? null : onTap,
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(10),
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

  // ---------------------------------------------------------------------------
  // CHAT
  // ---------------------------------------------------------------------------

  void _openAppChat() {
    if (_leaving || !mounted) {
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
    if (_leaving || !mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor:
          AppColors.cardLight,
      builder: (_) => Consumer(
        builder:
            (context, ref, __) {
          final session = ref.watch(
            dailyCallSessionProvider,
          );

          return ListView(
            shrinkWrap: true,
            padding:
                const EdgeInsets.all(16),
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
                        session.participants
                            .isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          if (!_leaving) {
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
              ...session.participants
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
                                  _leaving
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
      // Never allow Flutter to pop this route automatically.
      //
      // We first perform Daily native cleanup and then pop manually.
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) {
        if (didPop || _leaving) {
          return;
        }

        _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _joining
              ? Stack(
                  children: [
                    const Center(
                      child:
                          CircularProgressIndicator(
                        color: Colors.white,
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
                            TextButton.styleFrom(
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
                                .all(24),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          children: [
                            const Icon(
                              Icons
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
                                        Colors
                                            .white,
                                    side:
                                        const BorderSide(
                                      color:
                                          Colors
                                              .white54,
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
                                  child:
                                      const Text(
                                    'Try again',
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
                          color: Colors.black,
                        )
                      : Builder(
                          builder:
                              (context) {
                            // Do not touch Daily controllers once
                            // teardown has started.
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
                                // Main video.
                                if (!_leaving &&
                                    session.client !=
                                        null)
                                  Positioned.fill(
                                    child: mainRemote !=
                                            null
                                        ? _remoteVideoTile(
                                            mainRemote.key,
                                            mainRemote.value,
                                          )
                                        : _localVideoTile(
                                            session,
                                          ),
                                  ),

                                // Microphone status.
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
                                              size: 16,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                // Thumbnails.
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

                                // Top bar.
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
                                            _leaving
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
                                                FontWeight
                                                    .w700,
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
                                            _leaving
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
                                              _leaving
                                                  ? null
                                                  : _openParticipants,
                                        ),
                                    ],
                                  ),
                                ),

                                // Raised hands.
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
                                              AppColors
                                                  .accent,
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
                                                      !_leaving
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

                                // Chat.
                                Positioned(
                                  right: 16,
                                  bottom: 100,
                                  child:
                                      FloatingActionButton(
                                    heroTag:
                                        'live-class-chat-fab',
                                    backgroundColor:
                                        AppColors
                                            .primary,
                                    onPressed:
                                        _leaving
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

                                // Bottom controls.
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
                                            _leaving
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
                                            _leaving
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
                                            _leaving
                                                ? null
                                                : _flipCamera,
                                      ),
                                      const SizedBox(
                                        width: 16,
                                      ),
                                      _CallControlButton(
                                        icon: Icons
                                            .call_end_rounded,
                                        color:
                                            AppColors
                                                .error,
                                        onPressed:
                                            _leaving
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
                                              _leaving
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
  ConsumerState<_LiveClassChatSheet>
      createState() =>
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
      controller.position.maxScrollExtent,
      duration:
          const Duration(milliseconds: 250),
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
          (context, scrollController) {
        _chatScrollController =
            scrollController;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context)
                .viewInsets
                .bottom,
          ),
          child: Container(
            decoration:
                const BoxDecoration(
              color:
                  AppColors.cardLight,
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(20),
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
                        BorderRadius
                            .circular(2),
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
                            (context, index) {
                          final msg =
                              messages[index];

                          final isMine =
                              msg.userId ==
                                  user?.id;

                          return Align(
                            alignment: isMine
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
                    error: (e, __) =>
                        Center(
                      child:
                          Text('$e'),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets
                            .all(12),
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
