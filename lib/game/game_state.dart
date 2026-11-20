import 'package:flutter/foundation.dart';

enum GameScreen {
  loading,
  mapOverview,
  playing,
  paused,
  gameOver,
  victory,
}

enum RunPhase {
  skyDrop('SKY DROP'),
  scramble('SPRINT'),
  yamanote('RAIL GRIND'),
  meijiDori('SPRINT'),
  finale('FINALE');

  const RunPhase(this.defaultBadge);
  final String defaultBadge;
}

class ShibuyaZone {
  const ShibuyaZone({
    required this.jpName,
    required this.enName,
    required this.startMeters,
  });

  final String jpName;
  final String enName;
  final double startMeters;

  String get displayLabel => '$jpName · $enName';
}

class ToastEvent {
  ToastEvent({
    required this.id,
    required this.label,
    required this.bonusText,
    required this.colorValue,
    required this.createdAt,
  });

  final int id;
  final String label;
  final String bonusText;
  final int colorValue;
  final double createdAt;
}

class GameState extends ChangeNotifier {
  static const double totalRouteMeters = 960.0;
  static const double scrambleEndMeters = 320.0;
  static const double yamanoteEndMeters = 620.0;
  static const double meijiEndMeters = 900.0;

  static const List<ShibuyaZone> zones = [
    ShibuyaZone(jpName: 'スクランブル交差点', enName: 'Scramble', startMeters: 0),
    ShibuyaZone(jpName: '道玄坂', enName: 'Dogenzaka', startMeters: 160),
    ShibuyaZone(jpName: '宮下公園', enName: 'Miyashita Park', startMeters: 280),
    ShibuyaZone(jpName: '山手線', enName: 'Yamanote Line', startMeters: 340),
    ShibuyaZone(jpName: '明治通り', enName: 'Meiji-dori', startMeters: 630),
    ShibuyaZone(jpName: '渋谷ストリーム', enName: 'Google Tokyo', startMeters: 860),
  ];

  GameScreen screen = GameScreen.loading;
  RunPhase phase = RunPhase.skyDrop;
  String actionBadge = 'SKY DROP';

  double loadingProgress = 0.0;
  String loadingLabel = 'Loading Shibuya...';

  int score = 0;
  int highScore = 0;
  double speedKmh = 0.0;
  double maxSpeedKmh = 0.0;
  int combo = 1;
  int maxCombo = 1;
  int signsLit = 0;
  int boostRingsHit = 0;
  int nearMisses = 0;
  double distanceMeters = 0.0;
  double elapsedSeconds = 0.0;

  bool autoPilotEnabled = false;
  bool muted = false;
  bool photoMode = false;
  String? crashReason;

  ToastEvent? activeToast;
  int _nextToastId = 1;

  double get routeProgress =>
      (distanceMeters / totalRouteMeters).clamp(0.0, 1.0);

  ShibuyaZone get currentZone {
    ShibuyaZone active = zones.first;
    for (final z in zones) {
      if (distanceMeters >= z.startMeters) {
        active = z;
      }
    }
    return active;
  }

  void setLoadingProgress(double value, [String? label]) {
    loadingProgress = value.clamp(0.0, 1.0);
    if (label != null) {
      loadingLabel = label;
    }
    notifyListeners();
  }

  void finishLoading() {
    loadingProgress = 1.0;
    screen = GameScreen.mapOverview;
    notifyListeners();
  }

  void startRun() {
    screen = GameScreen.playing;
    phase = RunPhase.skyDrop;
    actionBadge = 'SKY DROP';
    score = 0;
    speedKmh = 0.0;
    maxSpeedKmh = 0.0;
    combo = 1;
    maxCombo = 1;
    signsLit = 0;
    boostRingsHit = 0;
    nearMisses = 0;
    distanceMeters = 0.0;
    elapsedSeconds = 0.0;
    photoMode = false;
    crashReason = null;
    activeToast = null;
    notifyListeners();
  }

  void returnToMap() {
    screen = GameScreen.mapOverview;
    photoMode = false;
    activeToast = null;
    notifyListeners();
  }

  void togglePause() {
    if (screen == GameScreen.playing) {
      screen = GameScreen.paused;
      notifyListeners();
    } else if (screen == GameScreen.paused) {
      screen = GameScreen.playing;
      notifyListeners();
    }
  }

  void toggleAutoPilot() {
    autoPilotEnabled = !autoPilotEnabled;
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  void togglePhotoMode() {
    if (screen == GameScreen.victory) {
      photoMode = !photoMode;
      notifyListeners();
    }
  }

  void showToast(String label, String bonusText, {int colorValue = 0xFFFF5A1F}) {
    activeToast = ToastEvent(
      id: _nextToastId++,
      label: label,
      bonusText: bonusText,
      colorValue: colorValue,
      createdAt: elapsedSeconds,
    );
    notifyListeners();
  }

  void addComboPoints(
    int basePoints, {
    bool bumpCombo = true,
    String? toastLabel,
    String? toastBonus,
    int colorValue = 0xFFFF5A1F,
  }) {
    if (bumpCombo) {
      combo = (combo + 1).clamp(1, 12);
      if (combo > maxCombo) maxCombo = combo;
    }
    final gained = basePoints * combo;
    score += gained;
    if (score > highScore) highScore = score;
    if (toastLabel != null) {
      showToast(toastLabel, toastBonus ?? '+$gained', colorValue: colorValue);
    } else {
      notifyListeners();
    }
  }

  void recordBoostRing() {
    boostRingsHit += 1;
    addComboPoints(
      125,
      toastLabel: 'BOOST RING',
      toastBonus: '+1,500',
      colorValue: 0xFFFBBC04,
    );
  }

  void recordNearMiss({bool tokyoDrift = false}) {
    nearMisses += 1;
    addComboPoints(
      tokyoDrift ? 100 : 60,
      toastLabel: tokyoDrift ? 'TOKYO DRIFT NEAR MISS' : 'NEAR MISS',
      toastBonus: tokyoDrift ? '+1,000' : '+500',
      colorValue: 0xFFFF2A9D,
    );
  }

  void recordSignLit() {
    signsLit += 1;
    addComboPoints(
      90,
      toastLabel: 'NEON SIGN IGNITED',
      toastBonus: '+${90 * combo}',
      colorValue: 0xFF00E5FF,
    );
  }

  void recordWallToRail() {
    addComboPoints(
      150,
      toastLabel: 'WALL TO RAIL TRANSFER',
      toastBonus: '+1,500',
      colorValue: 0xFF00E5FF,
    );
  }

  void updateFrame({
    required double dt,
    required double currentSpeedKmh,
    required double currentDistanceMeters,
    required RunPhase currentPhase,
    required String currentActionBadge,
    required int passivePoints,
  }) {
    elapsedSeconds += dt;
    speedKmh = currentSpeedKmh;
    if (currentSpeedKmh > maxSpeedKmh) {
      maxSpeedKmh = currentSpeedKmh;
    }
    distanceMeters = currentDistanceMeters;
    phase = currentPhase;
    actionBadge = currentActionBadge;
    if (passivePoints > 0) {
      score += passivePoints;
      if (score > highScore) highScore = score;
    }

    if (activeToast != null && elapsedSeconds - activeToast!.createdAt > 1.45) {
      activeToast = null;
    }
    notifyListeners();
  }

  void triggerGameOver(String reason) {
    crashReason = reason;
    screen = GameScreen.gameOver;
    if (score > highScore) highScore = score;
    notifyListeners();
  }

  void triggerVictory() {
    phase = RunPhase.finale;
    actionBadge = 'FINALE';
    addComboPoints(
      500,
      bumpCombo: false,
      toastLabel: 'GOOGLE IGNITED!',
      toastBonus: '+6,000',
      colorValue: 0xFF4285F4,
    );
    screen = GameScreen.victory;
    if (score > highScore) highScore = score;
    notifyListeners();
  }
}
