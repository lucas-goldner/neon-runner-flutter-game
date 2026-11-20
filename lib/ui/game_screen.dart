import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as fs;

import '../game/game_state.dart';
import '../game/shibuya_scene_controller.dart';
import '../game/sound_fx.dart';
import 'hud_overlay.dart';
import 'loading_screen.dart';
import 'map_overview_screen.dart';

/// Main game screen hosting Flutter Scene's [SceneView], frame ticker,
/// desktop/web keyboard input (A/D, Space, S, Esc), and iOS touch swipes.
class NeonScrambleGameScreen extends StatefulWidget {
  const NeonScrambleGameScreen({super.key});

  @override
  State<NeonScrambleGameScreen> createState() => _NeonScrambleGameScreenState();
}

class _NeonScrambleGameScreenState extends State<NeonScrambleGameScreen>
    with SingleTickerProviderStateMixin {
  late final GameState _state;
  late final SoundFx _soundFx;
  late final ShibuyaSceneController _controller;
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();

  Duration _lastTick = Duration.zero;
  Offset? _dragStart;
  bool _swipeHandled = false;

  @override
  void initState() {
    super.initState();
    _state = GameState();
    _soundFx = SoundFx();
    _controller = ShibuyaSceneController(state: _state, soundFx: _soundFx);
    _controller.initialize();

    _ticker = createTicker((elapsed) {
      if (_lastTick == Duration.zero) {
        _lastTick = elapsed;
        return;
      }
      final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
      _lastTick = elapsed;
      _controller.tick(dt);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _controller.dispose();
    _state.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
      _controller.moveLane(-1);
    } else if (key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.arrowRight) {
      _controller.moveLane(1);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.arrowUp) {
      if (_state.screen == GameScreen.mapOverview) {
        _controller.startNewRun();
      } else {
        _controller.jump();
      }
    } else if (key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.arrowDown) {
      _controller.slide();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.keyP) {
      _state.togglePause();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragStart = details.localPosition;
    _swipeHandled = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_state.photoMode) {
      _controller.orbitPhotoCamera(details.delta.dx);
      return;
    }
    if (_swipeHandled || _dragStart == null) return;
    final delta = details.localPosition - _dragStart!;
    if (delta.distance < 26) return;

    _swipeHandled = true;
    if (delta.dx.abs() > delta.dy.abs()) {
      _controller.moveLane(delta.dx > 0 ? 1 : -1);
    } else if (delta.dy < 0) {
      _controller.jump();
    } else {
      _controller.slide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060914),
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusNode.requestFocus(),
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          child: AnimatedBuilder(
            animation: _state,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (_controller.initialized)
                    fs.SceneView(
                      _controller.scene,
                      cameraBuilder: _controller.buildCamera,
                    ),

                  if (_state.screen == GameScreen.loading)
                    LoadingScreen(
                      progress: _state.loadingProgress,
                      label: _state.loadingLabel,
                    ),

                  if (_state.screen == GameScreen.mapOverview)
                    MapOverviewScreen(
                      onPlay: () {
                        _focusNode.requestFocus();
                        _controller.startNewRun();
                      },
                    ),

                  if (_state.screen != GameScreen.loading &&
                      _state.screen != GameScreen.mapOverview)
                    HudOverlay(
                      state: _state,
                      onToggleAutoPilot: _state.toggleAutoPilot,
                      onToggleMute: () {
                        _state.toggleMute();
                        _soundFx.muted = _state.muted;
                      },
                      onTogglePause: _state.togglePause,
                      onTogglePhotoMode: _state.togglePhotoMode,
                      onPlayAgain: _controller.startNewRun,
                      onReturnToMap: _state.returnToMap,
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
