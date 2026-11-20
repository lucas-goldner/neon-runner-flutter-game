import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'game_state.dart';
import 'hero_sim.dart';
import 'level_data.dart';
import 'glb_library.dart';
import 'pegman_builder.dart';
import 'pegman_glb.dart';
import 'pegman_pose.dart';
import 'route_spline.dart';
import 'sound_fx.dart';
import 'world_builder.dart';
import 'world_textures.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// Owns the Flutter Scene world for Neon Scramble: builds the OSM Shibuya
/// level, runs [HeroSim] and drives Pegman, traffic and the camera rigs
/// ported from the web demo (`computeCameraState`).
class ShibuyaSceneController {
  ShibuyaSceneController({required this.state, required this.soundFx});

  final GameState state;
  final SoundFx soundFx;
  final fs.Scene scene = fs.Scene();

  bool initialized = false;
  late final ShibuyaLevel level;
  late final HeroSim sim;
  late final ShibuyaWorld world;
  late final GlbPegman pegman;
  final PegmanPoseSolver _poseSolver = PegmanPoseSolver();
  final PoseParams _poseParams = PoseParams();
  late final GlbLibrary glb;
  final List<fs.Node> _taxiNodes = [];
  final List<fs.Node> _driftNodes = [];
  final List<fs.Node> _rain = [];
  final List<_Train> _trains = [];
  final math.Random _rng = math.Random(7);

  // camera state (reference coordinates)
  final vm.Vector3 camPos = vm.Vector3(68, 435, 68);
  final vm.Vector3 camTarget = vm.Vector3(68, 0, 68);
  vm.Vector3 camUp = vm.Vector3(0, 0, -1);
  double camFov = 54;
  double camRoll = 0;
  final vm.Vector3 _springPos = vm.Vector3(68, 435, 68);
  final vm.Vector3 _springVel = vm.Vector3.zero();
  final vm.Vector3 _springTgt = vm.Vector3(68, 0, 68);
  final vm.Vector3 _springTgtVel = vm.Vector3.zero();
  bool _camInit = false;
  double photoOrbit = 0;
  double photoZoom = 1;
  double _time = 0;
  int _lastCalloutId = -1;

  Future<void> initialize() async {
    state.setLoading(0.06, 'Loading Neon Scramble...');
    await fs.Scene.initializeStaticResources();
    state.setLoading(0.18, 'Loading Shibuya...');
    level = await ShibuyaLevel.load();
    sim = HeroSim(level, state);
    state.setLoading(0.32, 'Lighting Shibuya night sky...');
    _configureLighting();
    int loaded = 0;
    glb = await GlbLibrary.load(
        onProgress: (l) => state.setLoading(0.32 + 0.06 * ++loaded, l));
    state.setLoading(0.66, 'Preparing Shibuya Crossing...');
    final tex = await WorldTextures.create(level);
    state.setLoading(0.74, 'Building Shibuya streets...');
    world = ShibuyaWorld(level, sim.spline, tex, glb);
    await world.buildCity();
    world.build();
    await world.glbWorld.buildSigns();
    scene.add(world.root);
    state.setLoading(0.8, 'Preparing Pegman...');
    pegman = GlbPegman(glb)..attach(world.refRoot);
    state.setLoading(0.86, 'Loading Tokyo street fleet...');
    _buildTraffic();
    _buildTrains();
    _buildRain();
    state.setLoading(0.95, 'Placing Shibuya Stream...');
    initialized = true;
    state.setLoading(1.0, 'Shibuya ready');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    state.finishLoading();
  }

  void _configureLighting() {
    // Port of the demo's renderer/shadow-rig setup: moonlit sky dome
    // (#0F1D3A → #233C6B → #375789), hemisphere light #7AA4E6/#384B6B @0.42,
    // moon from (0.7427, 0.48, -0.4737) colour #DBEAFF @0.56, warm city rim
    // light, haze #1E345D @3.2e-4, AgX at exposure 1.18 with light bloom,
    // vignette 0.14 and film grain.
    final sky = fs.GradientSkySource(
      zenithColor: vm.Vector3(0.0085, 0.0220, 0.0680),
      horizonColor: vm.Vector3(0.0520, 0.1220, 0.2960),
      groundColor: vm.Vector3(0.0055, 0.0095, 0.0220),
      sunColor: vm.Vector3.zero(),
    );
    scene.skybox = fs.Skybox(sky);
    // Hemisphere-like IBL: bake a sky/ground gradient in the hemi colours.
    scene.environment = fs.EnvironmentMap.fromSky(fs.GradientSkySource(
      zenithColor: vm.Vector3(0.195, 0.371, 0.791) * 0.42,
      horizonColor: vm.Vector3(0.11, 0.2, 0.42) * 0.42,
      groundColor: vm.Vector3(0.040, 0.069, 0.147) * 0.42,
      sunColor: vm.Vector3.zero(),
    ));
    scene.environmentIntensity = 1.0;
    scene.toneMapping = fs.ToneMappingMode.agx;
    scene.exposure = 1.18;
    final moon = vm.Vector3(0.7427, 0.48, -0.4737).normalized();
    scene.directionalLight = fs.DirectionalLight(
      direction: w3(-moon.x, -moon.y, -moon.z),
      color: vm.Vector3(0.716, 0.823, 1.0),
      intensity: 0.56 + 0.68 * 0.35,
    );
    scene.fog
      ..enabled = true
      ..mode = fs.FogMode.exponential
      ..color = vm.Vector3(0.0130, 0.0343, 0.1046)
      ..density = 0.0032;
    scene.postProcess.bloom
      ..enabled = true
      ..intensity = 0.32
      ..threshold = 1.0
      ..scatter = 0.62;
    scene.postProcess.vignette
      ..enabled = true
      ..intensity = 0.14;
    scene.postProcess.filmGrain
      ..enabled = true
      ..intensity = 0.012;
  }

  fs.Node _car(String type) {
    final t = GlbLibrary.template(glb.fleet, type) ??
        GlbLibrary.template(glb.fleet, 'CrownComfortTaxi')!;
    world.refRoot.add(t);
    return t;
  }

  void _buildTraffic() {
    for (final t in sim.taxis) {
      _taxiNodes.add(_car(t.type));
    }
    for (final c in sim.drift) {
      _driftNodes.add(_car(c.type));
    }
  }

  void _buildTrains() {
    final tracks = level.meta['yamanoteTracks'] as Map<String, dynamic>;
    for (int e = 0; e < 2; e++) {
      final pts = [
        for (final p in tracks[e == 0 ? 'outer' : 'inner'] as List<dynamic>)
          vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
              (p[2] as num).toDouble()),
      ];
      final cars = <fs.Node>[];
      for (int c = 0; c < 4; c++) {
        final t = GlbLibrary.template(glb.props, 'YamanoteTrain');
        if (t == null) return;
        GlbLibrary.forEachMaterial(t, (name, p) {
          String? hex;
          double k = 0;
          if (name == 'Yamanote_Lights') {
            hex = '#FFFBEB';
            k = 3.6;
          } else if (name == 'Yamanote_Windows') {
            hex = '#D4E9FF';
            k = 1.45;
          } else if (name == 'Yamanote_Stripe') {
            hex = '#34A853';
            k = 0.45;
          }
          if (hex != null) {
            p.material = GlbLibrary.clonePbr(p.material)
              ..emissiveFactor = hexColor(hex, k)
              ..emissiveStrength = 1;
          }
        });
        world.refRoot.add(t);
        cars.add(t);
      }
      _trains.add(_Train(Polyline3(pts), cars, e == 0 ? 360 : 625, e == 0 ? 1 : -1));
    }
  }

  void _syncTrains(double dt) {
    const minD = 345.0, maxD = 640.0, base = 8.2, spacing = 15.4;
    for (final n in _trains) {
      final total = n.path.length;
      final a = math.min(maxD, total - 10);
      if (dt > 1e-6) {
        final rem = n.dir > 0 ? a - n.distance : n.distance - minD;
        if (rem <= 0.35 && n.vel.abs() <= 0.85) n.dir = -n.dir;
        final r2 = n.dir > 0 ? a - n.distance : n.distance - minD;
        var target = base;
        if (r2 < 24) target = base * math.sqrt((r2 / 24).clamp(0.0, 1.0));
        final o = n.dir * target, s = 4.2 * dt;
        n.vel = (n.vel + (o - n.vel).clamp(-s, s)).clamp(-base, base);
        final c = n.distance + n.vel * dt;
        if (c >= a) {
          n.distance = a;
          n.vel = 0;
          n.dir = -1;
        } else if (c <= minD) {
          n.distance = minD;
          n.vel = 0;
          n.dir = 1;
        } else {
          n.distance = c;
        }
      }
      for (int e = 0; e < n.cars.length; e++) {
        final d = (n.distance - e * spacing).clamp(0.0, total);
        final tan = vm.Vector3.zero();
        final p = n.path.at(d / total, tan);
        n.cars[e].localTransform = GlbLibrary.slot(
            p.x, (level.meta['yamanoteTracks']['deckY'] as num).toDouble(), p.z,
            math.atan2(tan.x, tan.z));
      }
    }
  }

  void _buildRain() {
    final mat = unlit(vm.Vector4(0.55, 0.65, 0.85, 0.35))
      ..alphaMode = fs.AlphaMode.blend;
    final geo = fs.CuboidGeometry(vm.Vector3(0.012, 0.9, 0.012));
    for (int i = 0; i < 220; i++) {
      final n = fs.Node(mesh: fs.Mesh(geo, mat))
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.18);
      _rain.add(n);
      scene.add(n);
    }
  }

  // ----------------------------------------------------------- run flow
  void startNewRun() {
    if (!initialized) return;
    sim.reset();
    state.beginRun();
    pegman.resetTrail();
    _camInit = false;
    photoOrbit = 0;
    photoZoom = 1;
    for (final g in world.pinGates) {
      g.setLit(false);
    }
    for (final p in world.slidePortals) {
      p.setLit(false);
    }
    for (final l in world.googleLetters) {
      l.material.emissiveFactor = l.baseEmissive * 0.04;
    }
  }

  void moveLane(int dir) => sim.moveLane(dir);

  void jump() {
    if (state.phase == AppPhase.playing && !state.autoPilot) sim.pressJump();
  }

  void slide() {
    if (state.phase == AppPhase.playing && !state.autoPilot) sim.pressSlide();
  }

  void orbitPhotoCamera(double dx, [double dy = 0]) {
    photoOrbit += dx * 0.008;
  }

  void zoomPhotoCamera(double delta) {
    photoZoom = _clamp(photoZoom * (1 + delta * 0.0015), 0.4, 2.5);
  }

  void resetPhotoCamera() {
    photoOrbit = 0;
    photoZoom = 1;
  }

  // --------------------------------------------------------------- tick
  void tick(double dt) {
    if (!initialized) return;
    _time += dt;
    if (!state.photoMode) sim.step(dt);
    final c = state.callout;
    if (c != null && c.id != _lastCalloutId) {
      _lastCalloutId = c.id;
      if (c.accent == CalloutAccent.danger) {
        soundFx.playCrash();
      } else {
        soundFx.playBoostRing();
      }
    }
    _syncProps();
    _syncTrains(dt);
    _syncHero(dt);
    _computeCamera(dt);
    _syncRain(dt);
    state.tick(state.photoMode ? 0 : dt);
  }

  void _syncMapsMorph() {
    // mapsMorph = smootherstep(dropClock / 0.9); overlay a = 1 - smoothstep(.18, .92, morph)
    double morph;
    if (state.phase == AppPhase.loading || state.phase == AppPhase.mapsTitle) {
      morph = 0;
    } else if (state.phase == AppPhase.skyDrop) {
      morph = _qs(sim.dropClock / 0.9);
    } else {
      morph = 1;
    }
    final a = 1 - _sStep(0.18, 0.92, morph);
    world.mapsOverlay.visible = a > 0.01;
    world.mapsOverlayMat.baseColorFactor = vm.Vector4(0, 0, 0, a);
    world.mapsOverlayMat.emissiveFactor = vm.Vector4(a, a, a, 1);
    final pulse = (_time * 0.85) % 1;
    for (int i = 0; i < world.dropPin.length; i++) {
      final n = world.dropPin[i];
      n.visible = a > 0.01;
      if (i == 2) {
        final k = 1 + pulse * 0.45;
        final p = n.position;
        n.localTransform = vm.Matrix4.compose(p, vm.Quaternion.identity(), vm.Vector3(k, 1, k));
      }
    }
  }

  void _syncProps() {
    _syncMapsMorph();
    for (int i = 0; i < world.railMats.length && i < sim.rails.length; i++) {
      final hero = sim.rails[i].isHero;
      final active = sim.activeRail == i;
      // #FF4F00 x4.8 desaturates to pale peach under the demo's AgX grade.
      world.railMats[i].emissiveFactor = active
          ? hexColor('#FFA27A', 3.4)
          : (hero ? hexColor('#38BDF8', 1.55) : hexColor('#FF4F00', 0.72));
    }
    for (int i = 0; i < world.rings.length; i++) {
      world.rings[i].node.visible = !sim.ringHit[i];
    }
    for (int i = 0; i < world.pinGates.length; i++) {
      final lit = sim.gateLit[i];
      if (world.pinGates[i].lit != lit || lit) {
        world.pinGates[i].setLit(lit, 0.85 + 0.15 * math.sin(_time * 6));
      }
    }
    for (int i = 0; i < world.slidePortals.length; i++) {
      final lit = sim.portalDone[i];
      if (world.slidePortals[i].lit != lit) world.slidePortals[i].setLit(lit);
    }
    for (final l in world.googleLetters) {
      final i = l.letterIndex;
      if (i >= 0 && state.googleLettersLit[i]) {
        final k = 0.85 + 0.15 * math.sin(_time * 5 + i);
        l.material.emissiveFactor = vm.Vector4(
            l.baseEmissive.x * k, l.baseEmissive.y * k, l.baseEmissive.z * k, 1);
      }
    }
    final pulse = 1.6 + 1.2 * (0.5 + 0.5 * math.sin(_time * 3.2));
    world.beaconMat?.emissiveFactor = hexColor('#FBBC05', pulse);
    world.glbWorld.updateSigns(sim.s, 1 / 60, _time,
        finale: state.phase == AppPhase.finale,
        reset: state.phase == AppPhase.skyDrop || state.phase == AppPhase.mapsTitle);
    for (int i = 0; i < sim.taxis.length; i++) {
      final t = sim.taxis[i];
      final n = _taxiNodes[i];
      n.visible = t.active;
      n.localTransform = GlbLibrary.slot(t.x, t.y, t.z, t.yaw);
    }
    for (int i = 0; i < sim.drift.length; i++) {
      final c = sim.drift[i];
      final n = _driftNodes[i];
      n.localTransform = GlbLibrary.slot(c.x, 0, c.z, c.yaw);
    }
  }

  void _syncHero(double dt) {
    PegmanPose pose;
    switch (sim.move) {
      case SimMove.skyDrop:
        pose = sim.grounded ? PegmanPose.run : PegmanPose.skyDrop;
      case SimMove.sprint:
        pose = PegmanPose.run;
      case SimMove.stumble:
        pose = PegmanPose.stumble;
      case SimMove.vault:
      case SimMove.pinBeacon:
        pose = sim.flipStyle != 'none' ? PegmanPose.flip : PegmanPose.jump;
        if (sim.move == SimMove.pinBeacon && sim.grounded) pose = PegmanPose.run;
      case SimMove.slide:
        pose = PegmanPose.slide;
      case SimMove.railGrind:
        pose = PegmanPose.grind;
      case SimMove.wallRun:
        pose = PegmanPose.wallRun;
      case SimMove.finaleOrbit:
        pose = PegmanPose.dance;
    }
    final visible =
        state.phase != AppPhase.mapsTitle && state.phase != AppPhase.loading;
    pegman.root.visible = visible;
    pegman.placeRoot(sim.x, sim.y, sim.z, sim.yaw);
    // _updateHeroPose(): feed the demo's IK pose solver.
    final p = _poseParams;
    final now = sim.spline.sample(sim.s);
    final ahead = sim.spline.sample(sim.s + math.max(4.5, sim.speed * 0.25));
    var fyd = ahead.yaw - now.yaw;
    while (fyd > math.pi) {
      fyd -= 2 * math.pi;
    }
    while (fyd < -math.pi) {
      fyd += 2 * math.pi;
    }
    p
      ..move = switch (sim.move) {
        SimMove.skyDrop => PoseMove.skyDrop,
        SimMove.sprint => PoseMove.sprint,
        SimMove.vault => PoseMove.vault,
        SimMove.slide => PoseMove.slide,
        SimMove.railGrind => PoseMove.railGrind,
        SimMove.wallRun => PoseMove.wallRun,
        SimMove.stumble => PoseMove.stumble,
        SimMove.pinBeacon => PoseMove.pinBeacon,
        SimMove.finaleOrbit => PoseMove.finaleOrbit,
      }
      ..time = sim.elapsed
      ..gaitPhase = sim.gaitPhase
      ..speedMps = sim.speed
      ..curvature = now.kappa
      ..steerRate = _clamp(sim.lateralVel / 12, -1, 1)
      ..futureYawDelta = fyd
      ..verticalVel = sim.vy
      ..dropInProgress = _clamp(sim.dropClock / 3.5, 0, 1)
      ..timeSinceLand = sim.timeSinceLand
      ..slideProgress = _slideProgress()
      ..stumbleProgress = sim.stumbleTimer > 0 ? 1 - sim.stumbleTimer / 0.65 : 1
      ..wallSide = sim.wallSide
      ..railSide = sim.activeRail % 2 == 0 ? 1 : -1
      ..railSlope = sim.activeRail >= 0 ? sim.pitch : 0
      ..voltageKv = sim.voltage
      ..flipPhase = sim.flipPhase
      ..flipStyle = sim.flipStyle
      ..overchargeRatio = state.overchargeRatio;
    if (pose == PegmanPose.dance) p.time = _time;
    pegman.applyPose(_poseSolver.solve(p));
  }

  double _slideProgress() {
    var a = sim.slideTimer > 0 ? 1 - sim.slideTimer / 0.62 : 0.5;
    if (sim.move == SimMove.slide) {
      var duck = sim.fastFall;
      for (final pt in sim.portals) {
        if ((sim.s - (pt['s'] as num).toDouble()).abs() <= 2.4) duck = true;
      }
      if (duck) a = _clamp(a, 0.14, 0.86);
    }
    return a;
  }

  void _syncRain(double dt) {
    final c = w3(camPos.x, camPos.y, camPos.z);
    final visible = state.phase != AppPhase.mapsTitle &&
        state.phase != AppPhase.loading &&
        camPos.y < 120;
    for (final n in _rain) {
      n.visible = visible;
      if (!visible) continue;
      var p = n.position;
      p.y -= dt * 26;
      if (p.y < c.y - 14 || (p - c).length > 34) {
        p = vm.Vector3(c.x + (_rng.nextDouble() - 0.5) * 50,
            c.y + 4 + _rng.nextDouble() * 18, c.z + (_rng.nextDouble() - 0.5) * 50);
      }
      n.position = p;
    }
  }

  // ------------------------------------------------------------- camera
  void _spring(vm.Vector3 pos, vm.Vector3 vel, vm.Vector3 target, double dt) {
    const w = 13.5, zeta = 0.94;
    final n = 1 + 2 * zeta * w * dt;
    final r = w * w * dt;
    final i = dt * r;
    final inv = 1 / (n + i);
    for (int k = 0; k < 3; k++) {
      final x = (n * pos[k] + dt * vel[k] + i * target[k]) * inv;
      vel[k] = (vel[k] + r * (target[k] - x)) / n;
      pos[k] = x;
    }
  }

  static double _qs(double x) {
    final q = _clamp(x, 0, 1);
    return q * q * q * (q * (6 * q - 15) + 10);
  }

  static double _sStep(double e0, double e1, double x) {
    final q = _clamp((x - e0) / (e1 - e0), 0, 1);
    return q * q * (3 - 2 * q);
  }

  void _computeCamera(double dt) {
    final h = sim;
    final t = _time;
    final shake = sim.trauma * sim.trauma;
    final sx = math.sin(t * 37.1) * 0.42 * shake;
    final sy = math.sin(t * 41.7 + 1.3) * 0.34 * shake;
    final shakeRoll = math.sin(t * 29.3 + 0.7) * 0.048 * shake;

    if (state.photoMode) {
      _photoCamera();
      return;
    }
    if (state.phase == AppPhase.loading || state.phase == AppPhase.mapsTitle) {
      camPos.setValues(68, 435, 68);
      camTarget.setValues(68, 0, 68);
      camUp = vm.Vector3(0, 0, -1);
      camFov = 54;
      camRoll = 0;
      _springPos.setFrom(camPos);
      _springTgt.setFrom(camTarget);
      _camInit = true;
      return;
    }
    if (state.phase == AppPhase.finale) {
      final r = sim.rooftop;
      final face = ((level.meta['googleTower'] as Map<String, dynamic>)['facingYaw'] as num)
          .toDouble();
      final a = face + math.sin(t * 0.28) * 0.34;
      final o = 15.5 + math.cos(t * 0.28) * 1.4;
      final yy = r.y + 2.8 + math.sin(t * 0.42) * 0.45;
      sim.yaw = face + math.sin(t * 0.28) * 0.16;
      camPos.setValues(r.x + math.sin(a) * o + sx, yy + sy, r.z + math.cos(a) * o);
      camTarget.setValues(
          r.x - math.sin(face) * 1.2, r.y + 2.15, r.z - math.cos(face) * 1.2);
      camFov = 52;
      camRoll = shakeRoll;
      camUp = vm.Vector3(0, 1, 0);
      return;
    }
    final now = sim.spline.sample(h.s);
    final c = _clamp((h.speed - 22) / 22, 0, 1);
    final l = _lerp(4.5, 5.4, c);
    final u = h.move == SimMove.slide
        ? 1.56
        : (h.activeTransfer >= 0 ? 2.28 : _lerp(2.05, 2.38, c));
    final d = _lerp(13, 20, c);
    final f = sim.spline.sample(h.s + d);
    var px = h.x - now.tx * l + now.rx * (h.lateral * -0.18);
    var py = h.y + u;
    var pz = h.z - now.tz * l + now.rz * (h.lateral * -0.18);
    var gx = f.x + f.rx * (h.lateral * 0.42);
    var gy = h.y + _clamp((f.y - h.y) * 0.35, -1.4, 1.1) + 1.92;
    var gz = f.z + f.rz * (h.lateral * 0.42);
    var fov = 58 + c * 18;
    if (h.activeRail >= 0 || h.activeWall >= 0 || h.activeTransfer >= 0) {
      fov = math.max(fov, 70 + state.overchargeRatio * 8);
    }
    if (state.overchargeRatio > 0.05) {
      fov = math.max(fov, _lerp(68, 78, state.overchargeRatio));
    }
    fov = _clamp(fov, 56, 78);
    final launch = level.route['heroGoogleLaunch'] as Map<String, dynamic>;
    final trig = (launch['triggerS'] as num).toDouble();
    final fly = _sStep(trig - 8, trig + 14, h.s) *
        (1 - _sStep(sim.spline.length - 12, sim.spline.length + 2, h.s));
    if (fly > 0.001) {
      final sc = (level.meta['googleTower'] as Map<String, dynamic>)['signCenter']
          as List<dynamic>;
      px += now.rx * (-3.4 * fly) - now.tx * (1.8 * fly);
      py += -0.35 * fly;
      pz += now.rz * (-3.4 * fly) - now.tz * (1.8 * fly);
      gx = _lerp(gx, (sc[0] as num).toDouble(), 0.5 * fly);
      gy = _lerp(gy, (sc[1] as num).toDouble() + 3.2, 0.5 * fly);
      gz = _lerp(gz, (sc[2] as num).toDouble(), 0.5 * fly);
      fov = _lerp(fov, 68, fly * 0.65);
    }

    final w = sim.dropClock;
    if (state.phase == AppPhase.skyDrop || w < 3.5) {
      double nx, ny, nz, ox, oy, oz, upY = 1, upZ = 0, fv = 60;
      if (w < 0.9) {
        final e = _qs(w / 0.9);
        nx = _lerp(68, h.x - now.tx * 9.5, e);
        ny = _lerp(435, 285, e);
        nz = _lerp(68, h.z - now.tz * 9.5, e);
        ox = _lerp(68, h.x + now.tx * 12, e);
        oy = _lerp(0, math.max(0, h.y - 45), e);
        oz = _lerp(68, h.z + now.tz * 12, e);
        final p = e, m = e - 1;
        final hh = math.max(1e-4, math.sqrt(p * p + m * m));
        upY = p / hh;
        upZ = m / hh;
        fv = _lerp(54, 66, e);
      } else if (w < 3.05) {
        final e = _clamp((w - 0.9) / 2.15, 0, 1);
        final dd = _qs(e);
        final back = _lerp(9.5, l + 1.1, dd);
        final up = _lerp(13, u + 1.6, dd);
        nx = h.x - now.tx * back;
        ny = h.y + up;
        nz = h.z - now.tz * back;
        final m = _qs(_clamp((e - 0.65) / 0.35, 0, 1));
        final hx = h.x + now.tx * _lerp(12, 10, dd);
        final hy = math.max(0.5, h.y - _lerp(45, 1.5, dd));
        final hz = h.z + now.tz * _lerp(12, 10, dd);
        ox = _lerp(hx, gx, m);
        oy = _lerp(hy, gy, m);
        oz = _lerp(hz, gz, m);
        fv = _lerp(66, 74, math.sin(e * math.pi));
      } else {
        final e = _qs(_clamp((w - 3.05) / 0.45, 0, 1));
        nx = _lerp(h.x - now.tx * (l + 1.1), px, e);
        ny = _lerp(h.y + u + 1.6, py, e);
        nz = _lerp(h.z - now.tz * (l + 1.1), pz, e);
        ox = _lerp(h.x + now.tx * 10, gx, e);
        oy = _lerp(h.y + 1.1, gy, e);
        oz = _lerp(h.z + now.tz * 10, gz, e);
        fv = _lerp(66, fov, e);
      }
      final inv = 1 / math.max(dt, 1e-4);
      if (_camInit) {
        _springVel.setValues((nx - _springPos.x) * inv,
            (ny - _springPos.y) * inv, (nz - _springPos.z) * inv);
        _springTgtVel.setValues((ox - _springTgt.x) * inv,
            (oy - _springTgt.y) * inv, (oz - _springTgt.z) * inv);
      }
      _springPos.setValues(nx, ny, nz);
      _springTgt.setValues(ox, oy, oz);
      camPos.setValues(nx + sx, ny + sy, nz);
      camTarget.setValues(ox, oy, oz);
      camFov = fv;
      camRoll = shakeRoll;
      camUp = vm.Vector3(0, upY, upZ);
      _camInit = true;
      return;
    }
    if (!_camInit) {
      _springPos.setValues(px, py, pz);
      _springTgt.setValues(gx, gy, gz);
      _camInit = true;
    } else {
      _spring(_springPos, _springVel, vm.Vector3(px, py, pz), dt);
      _spring(_springTgt, _springTgtVel, vm.Vector3(gx, gy, gz), dt);
    }
    final bob = 0.022 * math.sin(t * 2.1);
    camPos.setValues(_springPos.x + sx, _springPos.y + bob + sy, _springPos.z);
    camTarget.setFrom(_springTgt);
    camFov = _lerp(camFov, fov, 0.14);
    camRoll = _lerp(camRoll, -sim.bank * 0.24 + shakeRoll, 0.18);
    camUp = vm.Vector3(0, 1, 0);
  }

  void _photoCamera() {
    vm.Vector3 pos, tgt;
    double fov;
    switch (state.photoPreset) {
      case PhotoPreset.scramble:
        pos = vm.Vector3(-72, 26, 22);
        tgt = vm.Vector3(-10, 4.5, -18);
        fov = 54;
      case PhotoPreset.skyline:
        final gt = level.meta['googleTower'] as Map<String, dynamic>;
        final e = gt['signCenter'] as List<dynamic>;
        final yaw = (gt['facingYaw'] as num).toDouble();
        pos = vm.Vector3((e[0] as num).toDouble() + math.sin(yaw - 0.12) * 38,
            29, (e[2] as num).toDouble() + math.cos(yaw - 0.12) * 38);
        tgt = vm.Vector3(253, 24.5, 236);
        fov = 54;
      case PhotoPreset.hero:
        final n = sim.yaw + 0.62;
        pos = vm.Vector3(sim.x - math.sin(n) * 4.4, sim.y + 1.85,
            sim.z - math.cos(n) * 4.4);
        tgt = vm.Vector3(sim.x, sim.y + 1.15, sim.z);
        fov = 50;
    }
    final off = (pos - tgt) * photoZoom;
    final ca = math.cos(photoOrbit), sa = math.sin(photoOrbit);
    final rx = off.x * ca - off.z * sa, rz = off.x * sa + off.z * ca;
    camPos.setValues(tgt.x + rx, tgt.y + off.y, tgt.z + rz);
    camTarget.setFrom(tgt);
    camFov = fov;
    camUp = vm.Vector3(0, 1, 0);
    camRoll = 0;
  }

  fs.Camera buildCamera(Duration elapsed) {
    final pos = w3(camPos.x, camPos.y, camPos.z);
    final tgt = w3(camTarget.x, camTarget.y, camTarget.z);
    var up = vm.Vector3(camUp.x, camUp.y, -camUp.z);
    if (camRoll.abs() > 1e-4) {
      final fwd = (tgt - pos).normalized();
      up = vm.Quaternion.axisAngle(fwd, camRoll).rotated(up);
    }
    return fs.PerspectiveCamera(
      fovRadiansY: camFov * vm.degrees2Radians,
      position: pos,
      target: tgt,
      up: up,
      fovNear: 0.15,
      fovFar: 2500,
    );
  }

  void dispose() {}
}

class _Train {
  _Train(this.path, this.cars, this.distance, this.dir) : vel = 8.2 * dir;
  final Polyline3 path;
  final List<fs.Node> cars;
  double distance;
  double dir;
  double vel;
}
