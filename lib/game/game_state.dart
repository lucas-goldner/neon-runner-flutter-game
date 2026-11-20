import 'package:flutter/foundation.dart';

/// App phases, mirroring the web demo's `APP_PHASES`
/// (LOADING → MAPS_TITLE → SKY_DROP → PLAYING → FINALE).
enum AppPhase { loading, mapsTitle, skyDrop, playing, finale }

/// Parkour move shown in the HUD move badge (`data-move` in the web demo).
enum ParkourMove {
  skyDrop('SKY DROP'),
  sprint('SPRINT'),
  overcharge('OVERCHARGE'),
  jump('JUMP'),
  airFlip('AIR FLIP'),
  slide('SLIDE'),
  railGrind('RAIL GRIND'),
  wallRun('WALL RUN'),
  roofVault('ROOF VAULT'),
  neonSlide('NEON SLIDE'),
  pinBeacon('BOOST'),
  stumble('STUMBLE'),
  carDeflect('DEFLECT'),
  hoodBounce('BOUNCE'),
  sideDeflect('SIDE DEFLECT'),
  finaleOrbit('FINALE');

  const ParkourMove(this.label);
  final String label;
}

/// Accent of the bottom-center action callout (`data-accent`).
enum CalloutAccent { neon, gold, danger, google, vault, neonSlide }

enum PhotoPreset { hero, scramble, skyline }

class ActionCallout {
  ActionCallout({
    required this.id,
    required this.label,
    required this.bonus,
    required this.accent,
    required this.createdAt,
    this.duration = 1.6,
  });

  final int id;
  final String label;

  /// e.g. `+1,500`; empty string hides the `·` separator and bonus.
  final String bonus;
  final CalloutAccent accent;
  final double createdAt;
  final double duration;
}

/// One named street segment of the route (minimap header).
class StreetSegment {
  const StreetSegment({
    required this.sStart,
    required this.sEnd,
    required this.ja,
    required this.miniEn,
    this.shield,
  });

  final double sStart;
  final double sEnd;
  final String ja;
  final String miniEn;
  final String? shield;

  /// Minimap header text, e.g. `渋谷スクランブル · Scramble`.
  String get headerLabel => '$ja · $miniEn';
}

/// Observable game state shared by the 3D controller and the Flutter HUD.
class GameState extends ChangeNotifier {
  static const double overchargeKmh = 130.0;

  AppPhase phase = AppPhase.loading;
  ParkourMove move = ParkourMove.skyDrop;

  double loadingProgress = 0.0;
  String loadingLabel = 'Loading Shibuya...';

  int score = 0;
  double speedKmh = 0.0;
  double maxSpeedKmh = 0.0;
  int combo = 1;
  double runTimeSec = 0.0;
  double elapsed = 0.0;

  /// 0..1 overcharge meter (speed above the cruise target).
  double overchargeRatio = 0.0;

  /// Distance along the route spline in meters and the route length.
  double routeS = 0.0;
  double routeLength = 1047.1;

  /// Hero world position on the ground plane (meters, three.js frame:
  /// +X east, +Z south) and heading for the minimap.
  double heroX = -48.0;
  double heroZ = -5.2;
  double heroHeading = 1.485;

  StreetSegment? street;

  bool autoPilot = false;
  bool muted = false;
  bool photoMode = false;
  PhotoPreset photoPreset = PhotoPreset.hero;

  /// Onboarding hint pill: shown for the first seconds of the run.
  bool onboardingVisible = false;

  /// Google sign letters (G o o g l e) ignited during the finale.
  final List<bool> googleLettersLit = List<bool>.filled(6, false);

  ActionCallout? callout;
  int _nextCalloutId = 1;

  bool get isGameplay =>
      phase == AppPhase.skyDrop ||
      phase == AppPhase.playing ||
      phase == AppPhase.finale;

  bool get speedOvercharge =>
      phase == AppPhase.playing &&
      (speedKmh >= overchargeKmh || overchargeRatio >= 0.58);

  bool get highChain => combo >= 4;

  /// Badge shown in the telemetry pill.
  ParkourMove get displayMove {
    if (phase == AppPhase.skyDrop) return ParkourMove.skyDrop;
    if (speedOvercharge && move == ParkourMove.sprint) {
      return ParkourMove.overcharge;
    }
    return move;
  }

  void setLoading(double value, String label) {
    loadingProgress = value.clamp(0.0, 1.0);
    loadingLabel = label;
    notifyListeners();
  }

  void finishLoading() {
    loadingProgress = 1.0;
    phase = AppPhase.mapsTitle;
    notifyListeners();
  }

  void beginRun() {
    phase = AppPhase.skyDrop;
    move = ParkourMove.skyDrop;
    score = 0;
    speedKmh = 0;
    maxSpeedKmh = 0;
    combo = 1;
    runTimeSec = 0;
    overchargeRatio = 0;
    routeS = 0;
    photoMode = false;
    photoPreset = PhotoPreset.hero;
    onboardingVisible = false;
    callout = null;
    for (int i = 0; i < 6; i++) {
      googleLettersLit[i] = false;
    }
    notifyListeners();
  }

  void landFromSkyDrop() {
    phase = AppPhase.playing;
    move = ParkourMove.sprint;
    onboardingVisible = true;
    notifyListeners();
  }

  void enterFinale() {
    phase = AppPhase.finale;
    move = ParkourMove.finaleOrbit;
    onboardingVisible = false;
    notifyListeners();
  }

  void toggleAutoPilot() {
    autoPilot = !autoPilot;
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    notifyListeners();
  }

  void togglePhotoMode() {
    if (!isGameplay) return;
    photoMode = !photoMode;
    notifyListeners();
  }

  void setPhotoPreset(PhotoPreset p) {
    photoPreset = p;
    notifyListeners();
  }

  void dismissOnboarding() {
    if (!onboardingVisible) return;
    onboardingVisible = false;
    notifyListeners();
  }

  void showCallout(
    String label, {
    String bonus = '',
    CalloutAccent accent = CalloutAccent.neon,
    double duration = 1.6,
  }) {
    callout = ActionCallout(
      id: _nextCalloutId++,
      label: label,
      bonus: bonus,
      accent: accent,
      createdAt: elapsed,
      duration: duration,
    );
    notifyListeners();
  }

  /// Adds points (multiplied by the current combo) and optionally bumps it.
  int award(int basePoints, {bool bumpCombo = false}) {
    if (bumpCombo) combo = (combo + 1).clamp(1, 12);
    final gained = basePoints * combo;
    score += gained;
    return gained;
  }

  void resetCombo() {
    combo = 1;
  }

  static String formatInt(int v) {
    final s = v.abs().toString();
    final buf = StringBuffer(v < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// `mm:ss.t` run timer used by the finale banner.
  static String formatRunTime(double sec) {
    final m = sec ~/ 60;
    final s = sec - m * 60;
    return '${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(1).padLeft(4, '0')}';
  }

  /// Per-frame update from the controller; one notify per frame.
  void tick(double dt) {
    elapsed += dt;
    if (phase == AppPhase.playing) runTimeSec += dt;
    if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;
    final c = callout;
    if (c != null && elapsed - c.createdAt > c.duration) callout = null;
    notifyListeners();
  }
}
