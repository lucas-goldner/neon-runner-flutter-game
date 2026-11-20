import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'game_state.dart';
import 'neon_palette.dart';
import 'pegman_builder.dart';
import 'sound_fx.dart';

enum ObstacleKind {
  jdmCar,
  taxi,
  barrier,
  overheadGate,
}

class _TrafficObstacle {
  _TrafficObstacle({
    required this.node,
    required this.kind,
    required this.lane,
    required this.z,
    required this.baseY,
    required this.halfWidth,
    required this.halfLength,
    required this.height,
    required this.speedZ,
  });

  final fs.Node node;
  final ObstacleKind kind;
  final int lane;
  double z;
  final double baseY;
  final double halfWidth;
  final double halfLength;
  final double height;
  final double speedZ;
  bool nearMissAwarded = false;
}

class _BoostRing {
  _BoostRing({
    required this.node,
    required this.lane,
    required this.y,
    required this.z,
  });

  final fs.Node node;
  final int lane;
  final double y;
  final double z;
  bool collected = false;
}

class _NeonSignProp {
  _NeonSignProp({
    required this.material,
    required this.baseEmissive,
    required this.z,
  });

  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 baseEmissive;
  final double z;
  bool ignited = false;
}

/// Manages the complete Flutter Scene 3D world for Neon Scramble:
/// Shibuya Scramble Crossing -> Dogenzaka/Miyashita -> Yamanote Viaduct ->
/// Meiji-dori -> Shibuya Stream Google Tokyo Finale Stage.
class ShibuyaSceneController {
  ShibuyaSceneController({
    required this.state,
    required this.soundFx,
  });

  final GameState state;
  final SoundFx soundFx;

  final fs.Scene scene = fs.Scene();
  late final PegmanRig pegman;

  bool initialized = false;

  // Lane coordinates (-1 = left, 0 = center, +1 = right)
  static const List<double> laneX = [-3.0, 0.0, 3.0];

  // Player kinematics
  int targetLane = 1; // index into laneX
  double playerX = 0.0;
  double playerVelX = 0.0;
  double playerY = 42.0;
  double playerVelY = 0.0;
  double playerZ = 0.0; // moves along -Z toward -totalRouteMeters
  double forwardSpeed = 0.0; // meters/sec
  double boostTimer = 0.0;
  double slideTimer = 0.0;
  double skyDropProgress = 0.0;
  double shakeTimer = 0.0;
  double photoOrbitAngle = 0.0;
  double _totalTime = 0.0;

  bool _wasWallRunning = false;

  final List<_TrafficObstacle> _obstacles = [];
  final List<_BoostRing> _boostRings = [];
  final List<_NeonSignProp> _signs = [];
  final math.Random _rng = math.Random(42);

  static vm.Vector4 _scaleRgb(vm.Vector4 c, double k) =>
      vm.Vector4(c.x * k, c.y * k, c.z * k, c.w);

  Future<void> initialize() async {
    state.setLoadingProgress(0.12, 'Initializing Flutter Scene GPU...');
    await fs.Scene.initializeStaticResources();

    state.setLoadingProgress(0.35, 'Configuring Shibuya night lighting...');
    _configureLightingAndPostProcess();

    state.setLoadingProgress(0.55, 'Building Shibuya Crossing & skyline...');
    pegman = PegmanRig()..attachToScene(scene);
    _buildRoadAndCrosswalk();
    _buildCitySkyline();
    _buildPinArchesAndSigns();

    state.setLoadingProgress(0.75, 'Constructing Yamanote Line viaduct...');
    _buildYamanoteViaduct();
    _buildSideRailsAndWallPanels();

    state.setLoadingProgress(0.90, 'Lighting Shibuya Stream Google stage...');
    _buildGoogleFinaleStage();
    _populateObstaclesAndRings();

    _resetPlayerForOverview();
    initialized = true;
    state.setLoadingProgress(1.0, 'Shibuya ready');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    state.finishLoading();
  }

  void _configureLightingAndPostProcess() {
    // Night-time Shibuya: dark navy ambient instead of the bright default
    // studio IBL, a navy gradient sky, cool moonlight and distance fog so the
    // skyline fades into the same deep blue haze as the web demo.
    scene.environment =
        fs.EnvironmentMap.constantDiffuse(vm.Vector3(0.020, 0.032, 0.075));
    scene.environmentIntensity = 1.0;
    scene.skybox = fs.Skybox(
      fs.GradientSkySource(
        zenithColor: vm.Vector3(0.004, 0.008, 0.022),
        horizonColor: vm.Vector3(0.020, 0.034, 0.075),
        groundColor: vm.Vector3(0.010, 0.016, 0.036),
        sunColor: vm.Vector3.zero(),
      ),
    );
    scene.toneMapping = fs.ToneMappingMode.agx;
    scene.exposure = 1.0;
    scene.directionalLight = fs.DirectionalLight(
      direction: vm.Vector3(-0.35, -1.0, -0.25),
      color: vm.Vector3(0.55, 0.68, 1.0),
      intensity: 0.55,
    );
    scene.fog
      ..enabled = true
      ..mode = fs.FogMode.exponential
      ..color = vm.Vector3(0.018, 0.030, 0.068)
      ..density = 0.011;
    scene.postProcess.bloom
      ..enabled = true
      ..intensity = 0.55
      ..threshold = 1.0
      ..scatter = 0.65;
  }

  void _buildRoadAndCrosswalk() {
    final asphaltMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = NeonPalette.asphaltBase
      ..metallicFactor = 0.25
      ..roughnessFactor = 0.22;

    // Ground street from z = +20 to z = -980
    final road = fs.Node(
      name: 'shibuya_road',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(14.0, 0.2, 1020.0)), asphaltMat),
    )..position = vm.Vector3(0, -0.1, -480.0);
    scene.add(road);

    // Sidewalks
    final sidewalkMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.05, 0.06, 0.09, 1.0)
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.65;

    for (final side in [-1.0, 1.0]) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(5.0, 0.35, 1020.0)), sidewalkMat),
        )..position = vm.Vector3(side * 9.5, 0.08, -480.0),
      );
    }

    // Shibuya Scramble Crossing diagonal & cardinal zebra stripes around z = 0..-28
    final stripeMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = NeonPalette.crosswalkBase
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.45
      ..emissiveFactor = NeonPalette.emissiveWhiteSoft;

    for (int i = -5; i <= 5; i++) {
      // Main forward crosswalk
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.55, 0.03, 4.2)), stripeMat),
        )..position = vm.Vector3(i * 1.15, 0.02, -6.0),
      );
      // Diagonal scramble stripes
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.55, 0.03, 5.2)), stripeMat),
        )
          ..position = vm.Vector3(i * 1.15, 0.02, -16.0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.58),
      );
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.55, 0.03, 5.2)), stripeMat),
        )
          ..position = vm.Vector3(i * 1.15, 0.02, -24.0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -0.58),
      );
    }

    // Orange glowing landing target ring at Scramble Crossing (z = -4)
    final targetRingMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.45, 0.15, 1.0)
      ..emissiveFactor = NeonPalette.emissiveOrange;
    scene.add(_buildOctagonRingNode(radius: 2.2, thickness: 0.10, material: targetRingMat)
      ..position = vm.Vector3(0, 0.06, -4.0)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2));

    // Lane dashes along street sections
    final dashMat = fs.UnlitMaterial()
      ..baseColorFactor = vm.Vector4(0.65, 0.72, 0.85, 0.8);
    for (double z = -34.0; z > -920.0; z -= 14.0) {
      if (z < -315 && z > -625) continue; // elevated Yamanote section
      for (final x in [-1.5, 1.5]) {
        scene.add(
          fs.Node(
            mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.14, 0.02, 4.2)), dashMat),
          )..position = vm.Vector3(x, 0.015, z),
        );
      }
    }
  }

  void _buildCitySkyline() {
    final darkTowerMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = NeonPalette.buildingDark
      ..metallicFactor = 0.35
      ..roughnessFactor = 0.55;

    final midTowerMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = NeonPalette.buildingMid
      ..metallicFactor = 0.42
      ..roughnessFactor = 0.45;

    final warmWindowMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.82, 0.45, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.3
      ..emissiveFactor = vm.Vector4(1.45, 0.92, 0.32, 1.0);

    final coolWindowMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.55, 0.78, 1.0, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.3
      ..emissiveFactor = vm.Vector4(0.45, 0.78, 1.35, 1.0);

    // Dense Shibuya skyscrapers lining both sides of the corridor
    for (double z = 12.0; z > -950.0; z -= 22.0) {
      for (final side in [-1.0, 1.0]) {
        final h = 16.0 + _rng.nextDouble() * 34.0;
        final w = 9.0 + _rng.nextDouble() * 6.0;
        final d = 14.0 + _rng.nextDouble() * 5.0;
        final x = side * (12.5 + w * 0.45 + _rng.nextDouble() * 3.5);

        final building = fs.Node(
          mesh: fs.Mesh(
            fs.CuboidGeometry(vm.Vector3(w, h, d)),
            _rng.nextBool() ? darkTowerMat : midTowerMat,
          ),
        )..position = vm.Vector3(x, h * 0.5, z);
        scene.add(building);

        // Warm amber / cool blue glowing window bands facing the street
        final winMat = _rng.nextDouble() < 0.72 ? warmWindowMat : coolWindowMat;
        final bandCount = (h / 5.5).floor().clamp(2, 6);
        final faceX = x - side * (w * 0.5 + 0.08);
        for (int b = 0; b < bandCount; b++) {
          final bandY = 3.2 + b * 4.6;
          if (bandY > h - 1.5) break;
          scene.add(
            fs.Node(
              mesh: fs.Mesh(
                fs.CuboidGeometry(vm.Vector3(0.12, 1.35, d * 0.76)),
                winMat,
              ),
            )..position = vm.Vector3(faceX, bandY, z),
          );
        }

        // Vertical glowing Shibuya neon billboards on alternating buildings
        if (_rng.nextDouble() < 0.65) {
          final emissive =
              NeonPalette.signEmissives[_rng.nextInt(NeonPalette.signEmissives.length)];
          final signMat = fs.PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.12, 0.14, 0.20, 1.0)
            ..metallicFactor = 0.2
            ..roughnessFactor = 0.25
            ..emissiveFactor = _scaleRgb(emissive, 0.45);

          final signH = 5.5 + _rng.nextDouble() * 6.5;
          final signNode = fs.Node(
            mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.35, signH, 2.2)), signMat),
          )..position = vm.Vector3(
              side * 8.4,
              5.5 + signH * 0.5,
              z + (_rng.nextDouble() - 0.5) * 6.0,
            );
          scene.add(signNode);
          _signs.add(
            _NeonSignProp(
              material: signMat,
              baseEmissive: emissive,
              z: signNode.position.z,
            ),
          );
        }
      }
    }
  }

  void _buildPinArchesAndSigns() {
    final whiteNeonMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.98, 1.0, 1.0)
      ..emissiveFactor = vm.Vector4(2.2, 2.35, 2.6, 1.0);

    final blueSignMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.04, 0.24, 0.68, 1.0)
      ..emissiveFactor = vm.Vector4(0.12, 0.55, 1.55, 1.0);

    final greenJrSignMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.05, 0.52, 0.22, 1.0)
      ..emissiveFactor = vm.Vector4(0.18, 1.45, 0.48, 1.0);

    // Street View Pin Arches placed along key Shibuya landmarks
    const archZs = [-48.0, -145.0, -255.0, -405.0, -555.0, -710.0, -835.0];
    for (final z in archZs) {
      final baseY = _trackElevationAtZ(z);
      final arch = fs.Node(name: 'pin_arch_$z')..position = vm.Vector3(0, baseY, z);

      // Left & right pillars
      arch.add(fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.32, 6.2, 0.32)), whiteNeonMat),
      )..position = vm.Vector3(-5.6, 3.1, 0));
      arch.add(fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.32, 6.2, 0.32)), whiteNeonMat),
      )..position = vm.Vector3(5.6, 3.1, 0));
      // Top crossbar
      arch.add(fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(11.5, 0.32, 0.32)), whiteNeonMat),
      )..position = vm.Vector3(0, 6.2, 0));

      // Glowing Google Maps Pin silhouette at arch crown
      arch.add(_buildOctagonRingNode(radius: 1.05, thickness: 0.14, material: whiteNeonMat)
        ..position = vm.Vector3(0, 5.2, 0));
      arch.add(fs.Node(
        mesh: fs.Mesh(fs.SphereGeometry(radius: 0.34), whiteNeonMat),
      )..position = vm.Vector3(0, 5.3, 0));
      scene.add(arch);
    }

    // Overhead Japanese highway / JR gantry signs
    for (double z = -85.0; z > -880.0; z -= 130.0) {
      final isYamanote = z < -320 && z > -620;
      final baseY = _trackElevationAtZ(z);
      final board = fs.Node(
        mesh: fs.Mesh(
          fs.CuboidGeometry(vm.Vector3(5.6, 2.2, 0.22)),
          isYamanote ? greenJrSignMat : blueSignMat,
        ),
      )..position = vm.Vector3(isYamanote ? 0.0 : 3.4, baseY + 6.8, z);
      scene.add(board);
    }
  }

  void _buildYamanoteViaduct() {
    final deckMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.09, 0.12, 1.0)
      ..metallicFactor = 0.25
      ..roughnessFactor = 0.6;

    final railMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.4, 0.95, 0.45, 1.0)
      ..metallicFactor = 0.7
      ..roughnessFactor = 0.2
      ..emissiveFactor = NeonPalette.emissiveYamanote;

    final tieMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.14, 0.14, 0.18, 1.0)
      ..metallicFactor = 0.15
      ..roughnessFactor = 0.75;

    // Elevated viaduct deck from z = -320 to z = -620 at y = 4.6
    scene.add(
      fs.Node(
        name: 'yamanote_deck',
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(11.6, 0.6, 300.0)), deckMat),
      )..position = vm.Vector3(0, 4.3, -470.0),
    );

    // Entry & exit glowing launch rails
    final rampRailMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.65, 0.2, 1.0)
      ..emissiveFactor = NeonPalette.emissiveOrange;

    // Entry ramp rail (-300..-322)
    scene.add(
      fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.28, 0.24, 24.0)), rampRailMat),
      )
        ..position = vm.Vector3(0, 2.3, -310.0)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.20),
    );

    // Three parallel glowing Yamanote rails on the viaduct
    for (final x in laneX) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.22, 0.18, 300.0)), railMat),
        )..position = vm.Vector3(x, 4.72, -470.0),
      );
    }

    // Railroad ties & steel overhead catenary gantries
    for (double z = -324.0; z > -616.0; z -= 4.5) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(9.6, 0.10, 0.42)), tieMat),
        )..position = vm.Vector3(0, 4.62, z),
      );
      if (z.abs().toInt() % 36 < 5) {
        for (final side in [-1.0, 1.0]) {
          scene.add(
            fs.Node(
              mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.35, 7.2, 0.35)), tieMat),
            )..position = vm.Vector3(side * 5.6, 8.2, z),
          );
        }
        scene.add(
          fs.Node(
            mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(11.6, 0.30, 0.30)), tieMat),
          )..position = vm.Vector3(0, 11.7, z),
        );
      }
    }
  }

  void _buildSideRailsAndWallPanels() {
    final grindRailMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.72, 0.25, 1.0)
      ..emissiveFactor = NeonPalette.emissiveOrange;

    final wallPanelMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.10, 0.65, 1.0, 0.42)
      ..alphaMode = fs.AlphaMode.blend
      ..emissiveFactor = _scaleRgb(NeonPalette.emissiveCyan, 0.75);

    // Street-level side grind rails & glowing cyan wall-run panels
    const railSpans = [
      (-110.0, -170.0, -1.0),
      (-205.0, -275.0, 1.0),
      (-665.0, -745.0, -1.0),
      (-770.0, -840.0, 1.0),
    ];

    for (final span in railSpans) {
      final startZ = span.$1;
      final endZ = span.$2;
      final side = span.$3;
      final len = (startZ - endZ).abs();
      final midZ = (startZ + endZ) * 0.5;

      // Glowing side rail at lane edge
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.24, 0.22, len)), grindRailMat),
        )..position = vm.Vector3(side * 3.1, 1.65, midZ),
      );

      // Holographic cyan wall-run panel on opposite side
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.18, 3.6, len * 0.75)), wallPanelMat),
        )..position = vm.Vector3(-side * 4.4, 2.6, midZ),
      );
    }
  }

  void _buildGoogleFinaleStage() {
    const stageZ = -GameState.totalRouteMeters;
    const stageY = 6.2;

    // Sweeping illuminated ramp up to the Shibuya Stream stage (-900..-950)
    final rampMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.10, 0.12, 0.18, 1.0)
      ..metallicFactor = 0.4
      ..roughnessFactor = 0.25;
    final rampRailMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.85, 0.45, 1.0)
      ..emissiveFactor = NeonPalette.emissiveOrange;

    scene.add(
      fs.Node(
        mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(6.8, 0.4, 52.0)), rampMat),
      )
        ..position = vm.Vector3(0, stageY * 0.5, stageZ + 32.0)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.12),
    );
    for (final side in [-1.0, 1.0]) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.22, 0.22, 52.0)), rampRailMat),
        )
          ..position = vm.Vector3(side * 3.3, stageY * 0.5 + 0.35, stageZ + 32.0)
          ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.12),
      );
    }

    // Dark stage deck
    final stageDeck = fs.Node(
      name: 'google_finale_stage',
      mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(22.0, 0.8, 18.0)), rampMat),
    )..position = vm.Vector3(0, stageY - 0.4, stageZ - 2.0);
    scene.add(stageDeck);

    // Concentric glowing white/gold center rings on the stage floor
    final stageRingMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.96, 0.85, 1.0)
      ..emissiveFactor = vm.Vector4(2.8, 2.4, 1.6, 1.0);
    for (final r in [1.6, 3.2]) {
      scene.add(_buildOctagonRingNode(radius: r, thickness: 0.14, material: stageRingMat)
        ..position = vm.Vector3(0, stageY + 0.06, stageZ)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2));
    }

    // Black steel concert truss frame behind Pegman
    final trussMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.07, 0.10, 1.0)
      ..metallicFactor = 0.8
      ..roughnessFactor = 0.35;
    for (final x in [-8.5, -4.2, 0.0, 4.2, 8.5]) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.28, 9.5, 0.28)), trussMat),
        )..position = vm.Vector3(x, stageY + 4.7, stageZ - 6.8),
      );
    }
    for (final y in [2.5, 6.2, 9.2]) {
      scene.add(
        fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(18.0, 0.25, 0.25)), trussMat),
        )..position = vm.Vector3(0, stageY + y, stageZ - 6.8),
      );
    }

    // Massive 3D glowing "Google" neon marquee blocks on the truss
    final gEmissives = NeonPalette.googleEmissives;
    final letterSpecs = [
      (-6.8, gEmissives[0], 2.4, 3.2), // G (Blue)
      (-4.0, gEmissives[1], 2.1, 2.2), // o (Red)
      (-1.4, gEmissives[2], 2.1, 2.2), // o (Yellow)
      (1.3, gEmissives[0], 2.1, 2.6), // g (Blue)
      (3.6, gEmissives[3], 0.85, 3.4), // l (Green)
      (5.9, gEmissives[1], 2.1, 2.2), // e (Red)
    ];

    for (final spec in letterSpecs) {
      final mat = fs.PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.95, 0.95, 0.98, 1.0)
        ..emissiveFactor = spec.$2;
      final lx = spec.$1;
      final lw = spec.$3;
      final lh = spec.$4;
      final cy = stageY + 4.6;
      final cz = stageZ - 6.2;

      if (lw < 1.2) {
        // Vertical 'l' bar
        scene.add(fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(0.55, lh, 0.45)), mat),
        )..position = vm.Vector3(lx, cy + 0.3, cz));
      } else {
        // Glowing neon ring-letter silhouette
        scene.add(_buildOctagonRingNode(
          radius: lw * 0.55,
          thickness: 0.32,
          material: mat,
        )..position = vm.Vector3(lx, cy, cz));
      }
    }
  }

  void _populateObstaclesAndRings() {
    final jdmBodyMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.08, 0.14, 1.0)
      ..metallicFactor = 0.85
      ..roughnessFactor = 0.18;
    final taxiBodyMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.72, 0.05, 1.0)
      ..metallicFactor = 0.45
      ..roughnessFactor = 0.28;
    final headlightMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.92, 1.0)
      ..emissiveFactor = vm.Vector4(2.8, 2.6, 2.2, 1.0);
    final taillightMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.1, 0.1, 1.0)
      ..emissiveFactor = NeonPalette.emissiveRed;
    final barrierMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.18, 1.0)
      ..emissiveFactor = _scaleRgb(NeonPalette.emissiveOrange, 0.75);
    final ringGoldMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.82, 0.25, 1.0)
      ..emissiveFactor = NeonPalette.emissiveOrange;
    final ringGreenMat = fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.35, 1.0, 0.55, 1.0)
      ..emissiveFactor = NeonPalette.emissiveYamanote;

    // Spawn street traffic, viaduct barriers, and octagonal boost rings
    for (double z = -58.0; z > -885.0; z -= 26.0) {
      final isViaduct = z < -325.0 && z > -615.0;
      final baseY = _trackElevationAtZ(z);
      final lane = _rng.nextInt(3);

      if (isViaduct) {
        // Construction barrier on Yamanote viaduct (jumpable)
        final node = fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(2.2, 1.05, 0.85)), barrierMat),
        )..position = vm.Vector3(laneX[lane], baseY + 0.65, z);
        scene.add(node);
        _obstacles.add(
          _TrafficObstacle(
            node: node,
            kind: ObstacleKind.barrier,
            lane: lane,
            z: z,
            baseY: baseY,
            halfWidth: 1.05,
            halfLength: 0.55,
            height: 1.15,
            speedZ: 0.0,
          ),
        );
      } else {
        // JDM coupe or Tokyo taxi
        final isTaxi = _rng.nextDouble() < 0.35;
        final carNode = fs.Node()..position = vm.Vector3(laneX[lane], baseY, z);
        carNode.add(fs.Node(
          mesh: fs.Mesh(
            fs.CuboidGeometry(vm.Vector3(1.85, 0.82, 4.1)),
            isTaxi ? taxiBodyMat : jdmBodyMat,
          ),
        )..position = vm.Vector3(0, 0.55, 0));
        carNode.add(fs.Node(
          mesh: fs.Mesh(
            fs.CuboidGeometry(vm.Vector3(1.52, 0.52, 2.0)),
            isTaxi ? taxiBodyMat : jdmBodyMat,
          ),
        )..position = vm.Vector3(0, 1.15, -0.15));
        // Glowing red taillights facing Pegman (+Z)
        carNode.add(fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(1.65, 0.16, 0.10)), taillightMat),
        )..position = vm.Vector3(0, 0.68, 2.06));
        // Bright headlights (-Z)
        carNode.add(fs.Node(
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(1.60, 0.16, 0.10)), headlightMat),
        )..position = vm.Vector3(0, 0.62, -2.06));

        scene.add(carNode);
        _obstacles.add(
          _TrafficObstacle(
            node: carNode,
            kind: isTaxi ? ObstacleKind.taxi : ObstacleKind.jdmCar,
            lane: lane,
            z: z,
            baseY: baseY,
            halfWidth: 0.95,
            halfLength: 2.1,
            height: 1.45,
            speedZ: isTaxi ? 4.0 : 7.5,
          ),
        );
      }

      // Place an octagonal Boost Ring every second segment in a safe lane
      if (z.abs().toInt() % 52 < 26) {
        final ringLane = (lane + 1) % 3;
        final ringY = baseY + (isViaduct ? 2.1 : 1.9);
        final ringNode = _buildOctagonRingNode(
          radius: 1.45,
          thickness: 0.14,
          material: isViaduct ? ringGreenMat : ringGoldMat,
        )..position = vm.Vector3(laneX[ringLane], ringY, z - 12.0);
        scene.add(ringNode);
        _boostRings.add(
          _BoostRing(node: ringNode, lane: ringLane, y: ringY, z: z - 12.0),
        );
      }
    }
  }

  fs.Node _buildOctagonRingNode({
    required double radius,
    required double thickness,
    required fs.Material material,
  }) {
    final ring = fs.Node();
    const sides = 8;
    final segLen = 2 * radius * math.tan(math.pi / sides) + thickness * 0.6;
    for (int i = 0; i < sides; i++) {
      final angle = (i / sides) * math.pi * 2;
      final seg = fs.Node(
        mesh: fs.Mesh(
          fs.CuboidGeometry(vm.Vector3(segLen, thickness, thickness)),
          material,
        ),
      )
        ..position = vm.Vector3(
          math.cos(angle) * radius,
          math.sin(angle) * radius,
          0,
        )
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), angle + math.pi / 2);
      ring.add(seg);
    }
    return ring;
  }

  double _trackElevationAtZ(double z) {
    final dist = (-z).clamp(0.0, GameState.totalRouteMeters);
    if (dist < 300.0) return 0.0;
    if (dist < 322.0) {
      final t = (dist - 300.0) / 22.0;
      return 4.65 * t;
    }
    if (dist < 618.0) return 4.65;
    if (dist < 638.0) {
      final t = (dist - 618.0) / 20.0;
      return 4.65 * (1.0 - t);
    }
    if (dist < 902.0) return 0.0;
    if (dist < 952.0) {
      final t = (dist - 902.0) / 50.0;
      return 6.2 * t;
    }
    return 6.2;
  }

  void _resetPlayerForOverview() {
    targetLane = 1;
    playerX = 0.0;
    playerVelX = 0.0;
    playerY = 44.0;
    playerVelY = 0.0;
    playerZ = -2.0;
    forwardSpeed = 0.0;
    boostTimer = 0.0;
    slideTimer = 0.0;
    skyDropProgress = 0.0;
    shakeTimer = 0.0;
    _wasWallRunning = false;
    pegman.resetTrail(vm.Vector3(playerX, playerY, playerZ));
  }

  void startNewRun() {
    _resetPlayerForOverview();
    for (final o in _obstacles) {
      o.nearMissAwarded = false;
    }
    for (final r in _boostRings) {
      r.collected = false;
      r.node.visible = true;
    }
    for (final s in _signs) {
      s.ignited = false;
      s.material.emissiveFactor = _scaleRgb(s.baseEmissive, 0.45);
    }
    state.startRun();
  }

  void moveLane(int delta) {
    if (state.screen != GameScreen.playing || state.phase == RunPhase.skyDrop) {
      return;
    }
    final next = (targetLane + delta).clamp(0, 2);
    if (next != targetLane) {
      targetLane = next;
      soundFx.playLaneSwitch();
    }
  }

  void jump() {
    if (state.screen != GameScreen.playing || state.phase == RunPhase.skyDrop) {
      return;
    }
    final groundY = _trackElevationAtZ(playerZ);
    if (playerY <= groundY + 0.18) {
      playerVelY = 12.6;
      slideTimer = 0.0;
      soundFx.playJump();
    }
  }

  void slide() {
    if (state.screen != GameScreen.playing || state.phase == RunPhase.skyDrop) {
      return;
    }
    slideTimer = 0.65;
    if (playerY > _trackElevationAtZ(playerZ) + 0.2) {
      playerVelY = -18.0; // fast slam
    }
    soundFx.playLaneSwitch();
  }

  void orbitPhotoCamera(double deltaX) {
    if (state.photoMode) {
      photoOrbitAngle += deltaX * 0.012;
    }
  }

  void tick(double dt) {
    if (!initialized) return;
    _totalTime += dt;

    if (state.screen == GameScreen.victory) {
      if (state.photoMode) {
        photoOrbitAngle += dt * 0.25;
      }
      pegman.updatePose(
        dt: dt,
        worldPosition: vm.Vector3(0, 6.2, -GameState.totalRouteMeters),
        laneVelocityX: 0,
        isSkyDrop: false,
        isSliding: false,
        isJumping: false,
        isGrinding: false,
        isWallRunning: false,
        isVictory: true,
        wallSide: 0,
        speedRatio: 0,
        time: _totalTime,
      );
      return;
    }

    if (state.screen != GameScreen.playing) return;

    if (shakeTimer > 0) {
      shakeTimer = (shakeTimer - dt).clamp(0.0, 1.0);
    }

    // Phase 1: SKY DROP into Shibuya Scramble Crossing
    if (state.phase == RunPhase.skyDrop) {
      skyDropProgress = (skyDropProgress + dt * 0.58).clamp(0.0, 1.0);
      final eased = 1.0 - math.pow(1.0 - skyDropProgress, 3.0).toDouble();
      playerY = 44.0 * (1.0 - eased);
      playerZ = -2.0 - eased * 3.0;
      pegman.updatePose(
        dt: dt,
        worldPosition: vm.Vector3(playerX, playerY, playerZ),
        laneVelocityX: 0,
        isSkyDrop: true,
        isSliding: false,
        isJumping: false,
        isGrinding: false,
        isWallRunning: false,
        isVictory: false,
        wallSide: 0,
        speedRatio: 0,
        time: _totalTime,
      );

      if (skyDropProgress >= 1.0) {
        forwardSpeed = 26.0;
        state.updateFrame(
          dt: dt,
          currentSpeedKmh: 94.0,
          currentDistanceMeters: 5.0,
          currentPhase: RunPhase.scramble,
          currentActionBadge: 'SPRINT',
          passivePoints: 0,
        );
      } else {
        state.updateFrame(
          dt: dt,
          currentSpeedKmh: 0.0,
          currentDistanceMeters: 0.0,
          currentPhase: RunPhase.skyDrop,
          currentActionBadge: 'SKY DROP',
          passivePoints: 0,
        );
      }
      return;
    }

    // Active running phases
    if (boostTimer > 0) {
      boostTimer = (boostTimer - dt).clamp(0.0, 3.0);
    }
    if (slideTimer > 0) {
      slideTimer = (slideTimer - dt).clamp(0.0, 1.0);
    }

    final dist = (-playerZ).clamp(0.0, GameState.totalRouteMeters);
    final baseSpeed = 28.0 + (dist / GameState.totalRouteMeters) * 12.0;
    final targetSpeed = baseSpeed + (boostTimer > 0 ? 9.5 : 0.0);
    forwardSpeed += (targetSpeed - forwardSpeed) * (dt * 4.5).clamp(0.0, 1.0);

    // Optional Auto-Pilot steering (matches video Auto-Pilot button)
    if (state.autoPilotEnabled) {
      _runAutoPilot();
    }

    // Advance Pegman forward (-Z)
    playerZ -= forwardSpeed * dt;
    final newDist = (-playerZ).clamp(0.0, GameState.totalRouteMeters);

    // Smooth lane lateral movement
    final desiredX = laneX[targetLane];
    final prevX = playerX;
    playerX += (desiredX - playerX) * (dt * 14.0).clamp(0.0, 1.0);
    playerVelX = (playerX - prevX) / (dt > 0.0001 ? dt : 0.016);

    // Vertical gravity & track elevation
    final groundY = _trackElevationAtZ(playerZ);
    playerVelY -= 32.0 * dt;
    playerY += playerVelY * dt;
    if (playerY <= groundY) {
      playerY = groundY;
      playerVelY = 0.0;
    }

    // Determine active phase & special mechanics
    final RunPhase phase;
    if (newDist < GameState.scrambleEndMeters) {
      phase = RunPhase.scramble;
    } else if (newDist < GameState.yamanoteEndMeters) {
      phase = RunPhase.yamanote;
    } else if (newDist < GameState.totalRouteMeters) {
      phase = RunPhase.meijiDori;
    } else {
      phase = RunPhase.finale;
    }

    final isJumping = playerY > groundY + 0.25;
    final isSliding = slideTimer > 0 && !isJumping;
    final isOnYamanote = phase == RunPhase.yamanote;
    final isOnSideRail = !isOnYamanote &&
        ((newDist > 110 && newDist < 170 && targetLane == 0) ||
            (newDist > 205 && newDist < 275 && targetLane == 2) ||
            (newDist > 665 && newDist < 745 && targetLane == 0) ||
            (newDist > 770 && newDist < 840 && targetLane == 2));
    final isWallRunning = !isOnYamanote &&
        ((newDist > 118 && newDist < 162 && targetLane == 2) ||
            (newDist > 212 && newDist < 268 && targetLane == 0) ||
            (newDist > 672 && newDist < 738 && targetLane == 2));

    if (_wasWallRunning && isOnSideRail) {
      state.recordWallToRail();
      soundFx.playBoostRing();
    }
    _wasWallRunning = isWallRunning;

    final isGrinding = isOnYamanote || isOnSideRail;
    final String badge;
    if (isSliding) {
      badge = 'SLIDE';
    } else if (isJumping) {
      badge = 'JUMP';
    } else if (isWallRunning) {
      badge = 'WALL RUN';
    } else if (isGrinding) {
      badge = 'RAIL GRIND';
    } else {
      badge = 'SPRINT';
    }

    // Update roadside neon signs — ignite as Pegman passes
    for (final s in _signs) {
      if (!s.ignited && (s.z - playerZ).abs() < 12.0) {
        s.ignited = true;
        s.material.emissiveFactor = _scaleRgb(s.baseEmissive, 1.45);
        state.recordSignLit();
      }
    }

    // Spin & check octagonal Boost Rings
    for (final r in _boostRings) {
      if (r.collected) continue;
      r.node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), _totalTime * 1.8);
      if ((r.z - playerZ).abs() < 2.2 && (laneX[r.lane] - playerX).abs() < 1.8) {
        r.collected = true;
        r.node.visible = false;
        boostTimer = 2.0;
        state.recordBoostRing();
        soundFx.playBoostRing();
      }
    }

    // Move traffic & check collisions / Tokyo Drift Near Misses
    for (final obs in _obstacles) {
      if (obs.speedZ > 0 && (obs.z - playerZ).abs() < 140.0) {
        obs.z += obs.speedZ * dt;
        obs.node.position = vm.Vector3(laneX[obs.lane], obs.baseY, obs.z);
      }

      final dz = (obs.z - playerZ).abs();
      final dx = (laneX[obs.lane] - playerX).abs();

      // Check collision
      if (dz < obs.halfLength + 0.45 && dx < obs.halfWidth + 0.35) {
        final clearHeight = obs.baseY + obs.height;
        if (playerY + 0.15 < clearHeight) {
          if (state.autoPilotEnabled) {
            // Auto-pilot vaults cleanly over any late obstacle
            playerVelY = 12.6;
          } else {
            shakeTimer = 0.45;
            soundFx.playCrash();
            state.triggerGameOver(
              obs.kind == ObstacleKind.barrier
                  ? 'Clipped a Yamanote viaduct barrier'
                  : 'Collided with Shibuya traffic',
            );
            return;
          }
        }
      } else if (!obs.nearMissAwarded &&
          obs.z > playerZ + 0.8 &&
          obs.z < playerZ + 5.5 &&
          dx < 3.4) {
        obs.nearMissAwarded = true;
        state.recordNearMiss(tokyoDrift: obs.kind == ObstacleKind.jdmCar);
      }
    }

    // Victory check at Shibuya Stream – Google Tokyo
    if (newDist >= GameState.totalRouteMeters) {
      soundFx.playVictory();
      state.triggerVictory();
      return;
    }

    final displayY = isOnSideRail && !isJumping ? groundY + 1.65 : playerY;
    pegman.updatePose(
      dt: dt,
      worldPosition: vm.Vector3(playerX, displayY, playerZ),
      laneVelocityX: playerVelX,
      isSkyDrop: false,
      isSliding: isSliding,
      isJumping: isJumping,
      isGrinding: isGrinding,
      isWallRunning: isWallRunning,
      isVictory: false,
      wallSide: targetLane == 0 ? -1.0 : 1.0,
      speedRatio: ((forwardSpeed - 24.0) / 24.0).clamp(0.0, 1.0),
      time: _totalTime,
    );

    final speedKmh = forwardSpeed * 3.6;
    final passivePts = (dt * (isGrinding || isWallRunning ? 140 : 65) * state.combo).round();
    state.updateFrame(
      dt: dt,
      currentSpeedKmh: speedKmh,
      currentDistanceMeters: newDist,
      currentPhase: phase,
      currentActionBadge: badge,
      passivePoints: passivePts,
    );
  }

  void _runAutoPilot() {
    // Look ahead for obstacles in our current lane
    for (final obs in _obstacles) {
      final ahead = playerZ - obs.z; // positive when obs is in front
      if (ahead > 4.0 && ahead < 24.0 && obs.lane == targetLane) {
        if (obs.kind == ObstacleKind.barrier) {
          jump();
        } else {
          // Pick a safe adjacent lane
          final candidates = [0, 1, 2]..remove(targetLane);
          candidates.sort((a, b) => (a - targetLane).abs().compareTo((b - targetLane).abs()));
          targetLane = candidates.first;
        }
        return;
      }
    }

    // Steer toward upcoming Boost Rings when lane is clear
    for (final ring in _boostRings) {
      if (ring.collected) continue;
      final ahead = playerZ - ring.z;
      if (ahead > 6.0 && ahead < 28.0) {
        targetLane = ring.lane;
        return;
      }
    }
  }

  fs.PerspectiveCamera buildCamera(Duration elapsed) {
    if (state.screen == GameScreen.victory) {
      const stageZ = -GameState.totalRouteMeters;
      const stageY = 6.2;
      final angle = state.photoMode ? photoOrbitAngle : math.sin(_totalTime * 0.45) * 0.16;
      const radius = 11.5;
      return fs.PerspectiveCamera(
        position: vm.Vector3(
          math.sin(angle) * radius,
          stageY + 3.4,
          stageZ + math.cos(angle) * radius,
        ),
        target: vm.Vector3(0, stageY + 2.6, stageZ - 2.5),
        fovRadiansY: 0.92,
      );
    }

    if (state.screen == GameScreen.mapOverview || state.phase == RunPhase.skyDrop) {
      // Smooth aerial descent from high above Shibuya Scramble Crossing into chase view
      final t = state.screen == GameScreen.mapOverview ? 0.0 : skyDropProgress;
      final eased = 1.0 - math.pow(1.0 - t, 2.5).toDouble();
      final camY = 58.0 * (1.0 - eased) + 4.8 * eased;
      final camZ = playerZ + 14.0 * (1.0 - eased) + 8.5 * eased;
      final lookY = playerY * (1.0 - eased) + 2.0 * eased;
      final lookZ = playerZ - 14.0 * eased;
      return fs.PerspectiveCamera(
        position: vm.Vector3(playerX * 0.4, camY, camZ),
        target: vm.Vector3(playerX * 0.4, lookY, lookZ),
        fovRadiansY: 0.98,
      );
    }

    final shakeX = shakeTimer > 0 ? math.sin(_totalTime * 55.0) * 0.35 * shakeTimer : 0.0;
    final shakeY = shakeTimer > 0 ? math.cos(_totalTime * 48.0) * 0.25 * shakeTimer : 0.0;
    final fovBoost = boostTimer > 0 ? 0.14 : 0.0;

    return fs.PerspectiveCamera(
      position: vm.Vector3(
        playerX * 0.72 + shakeX,
        playerY + 4.4 + shakeY,
        playerZ + 8.6,
      ),
      target: vm.Vector3(
        playerX * 0.55,
        playerY + 1.8,
        playerZ - 16.0,
      ),
      fovRadiansY: 1.02 + fovBoost,
    );
  }

  void dispose() {
    scene.dispose();
  }
}
