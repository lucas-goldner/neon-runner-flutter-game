import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audio + haptics: loops the demo's original `shibuya_bgm.mp3` soundtrack
/// (started from the PLAY gesture so browsers allow playback) and gives
/// haptic ticks for gameplay events on iOS.
class SoundFx {
  bool _muted = false;
  AudioPlayer? _bgm;
  bool _started = false;

  bool get muted => _muted;
  set muted(bool v) {
    _muted = v;
    _bgm?.setVolume(v ? 0 : 0.8);
  }

  Future<void> startMusic() async {
    if (_started) return;
    _started = true;
    try {
      final p = AudioPlayer();
      _bgm = p;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_muted ? 0 : 0.8);
      await p.play(AssetSource('audio/shibuya_bgm.mp3'));
    } catch (_) {
      _started = false; // e.g. autoplay blocked; retry on next gesture
    }
  }

  void playLaneSwitch() {
    if (_muted) return;
    HapticFeedback.selectionClick();
  }

  void playJump() {
    if (_muted) return;
    HapticFeedback.lightImpact();
  }

  void playBoostRing() {
    if (_muted) return;
    HapticFeedback.mediumImpact();
  }

  void playCrash() {
    if (_muted) return;
    HapticFeedback.heavyImpact();
  }

  void playVictory() {
    if (_muted) return;
    HapticFeedback.heavyImpact();
  }

  void dispose() {
    _bgm?.dispose();
  }
}
