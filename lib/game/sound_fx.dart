import 'package:flutter/services.dart';

/// Cross-platform audio & haptic feedback controller (iOS, macOS, Web).
/// Uses built-in SystemSound + HapticFeedback with zero native plugin overhead.
class SoundFx {
  bool muted = false;

  void playLaneSwitch() {
    if (muted) return;
    HapticFeedback.selectionClick();
  }

  void playJump() {
    if (muted) return;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void playBoostRing() {
    if (muted) return;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void playCrash() {
    if (muted) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  void playVictory() {
    if (muted) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }
}
