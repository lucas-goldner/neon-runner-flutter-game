import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'level_data.dart';
import 'world_builder.dart';

double _d(dynamic v, [double fb = 0]) => (v as num?)?.toDouble() ?? fb;

/// Places the demo's glTF models exactly like its `_attach*` / `_build*`
/// functions (positions, yaw offsets, scales), in the reference frame under
/// [ShibuyaWorld.refRoot].
class GlbWorld {
  GlbWorld(this.world, this.lib);

  final ShibuyaWorld world;
  final GlbLibrary lib;
  ShibuyaLevel get level => world.level;
  fs.Node get ref => world.refRoot;

  /// Rooftop target centre derived from `Podium_PinBeaconRing` (y ≥ 20).
  vm.Vector3 rooftop = vm.Vector3(242.89, 22, 257.3);
  fs.Node? mediaScreen;

  void build() {
    _googleTower();
    _heroArchitecture();
    _streetProps();
    _pinGates();
    _boostRings();
    _slideArches();
  }

  bool _inScramblePlaza(double x, double z) {
    final sc = level.meta['scrambleCrossing'] as Map<String, dynamic>;
    final c = sc['center'] as List<dynamic>;
    final r = _d(sc['radius'], 32);
    final dx = x - _d(c[0]), dz = z - _d(c[2]);
    return dx * dx + dz * dz < r * r;
  }

  // ------------------------------------------------ Google Stream tower
  void _googleTower() {
    final slot = (level.meta['heroArchSlots'] as Map<String, dynamic>)['googleStreamTower']
        as Map<String, dynamic>;
    final t = GlbLibrary.template(lib.googleTower, 'GoogleStreamTower');
    if (t == null) return;
    final r = _d(slot['yaw'], 2.68);
    final pos = slot['pos'] as List<dynamic>;
    final x = _d(pos[0]) - math.sin(r) * 29, z = _d(pos[2]) - math.cos(r) * 29;
    t.localTransform = GlbLibrary.slot(x, 0, z, r);
    // Rooftop centre from the pin beacon ring (local bbox centre (0, 22, 10.8)).
    rooftop = vm.Vector3(x + 10.8 * math.sin(r), 22, z + 10.8 * math.cos(r));

    // Per-letter materials so each of the six letters ignites on its own.
    const order = ['G', 'o1', 'o2', 'g', 'l', 'e'];
    const colors = ['#4285F4', '#EA4335', '#FBBC05', '#4285F4', '#34A853', '#EA4335'];
    for (int i = 0; i < 6; i++) {
      for (final prefix in ['NeonLetter_', 'Core_']) {
        final n = t.getChildByName('$prefix${order[i]}');
        if (n == null) continue;
        for (final (mn, _) in GlbLibrary.meshNodes(n)) {
          for (final p in mn.mesh!.primitives) {
            final m = GlbLibrary.clonePbr(p.material);
            final core = prefix == 'Core_';
            m.baseColorFactor = core ? hexColor('#1C273B') : hexColor(colors[i], 1, 0.34);
            if (!core) m.alphaMode = fs.AlphaMode.blend;
            m.emissiveStrength = 1;
            final lit = hexColor(colors[i], core ? 5.0 : 2.4);
            m.emissiveFactor = hexColor(colors[i], core ? 0.14 : 0.1);
            p.material = m;
            world.googleLetters.add(GlowProp(m, lit, litScale: 1.0, letterIndex: i));
          }
        }
      }
    }
    final ring = t.getChildByName('Podium_PinBeaconRing');
    if (ring != null && ring.mesh != null) {
      final m = GlbLibrary.clonePbr(ring.mesh!.primitives.first.material);
      for (final p in ring.mesh!.primitives) {
        p.material = m;
      }
      world.beaconMat = m;
    }
    ref.add(t);
  }

  // --------------------------------------------- hero architecture (arch)
  void _heroArchitecture() {
    final slots = level.meta['heroArchSlots'] as Map<String, dynamic>;
    void place(String node, Map<String, dynamic>? s) {
      if (s == null) return;
      final t = GlbLibrary.template(lib.arch, node);
      if (t == null) return;
      final p = s['pos'] as List<dynamic>;
      final sc = s['scale'] as List<dynamic>?;
      t.localTransform = GlbLibrary.slot(_d(p[0]), _d(p[1]), _d(p[2]), _d(s['yaw']),
          sc == null ? null : vm.Vector3(_d(sc[0], 1), _d(sc[1], 1), _d(sc[2], 1)));
      if (node == 'ScrambleMediaFacade') mediaScreen = t.getChildByName('MediaScreenSurface');
      ref.add(t);
    }

    place('ScrambleCornerLandmark', slots['scrambleCorner'] as Map<String, dynamic>?);
    place('Shibuya109Landmark', slots['shibuya109'] as Map<String, dynamic>?);
    place('ScrambleMediaFacade', slots['scrambleMediaFacade'] as Map<String, dynamic>?);

    List<vm.Matrix4> mats(List<dynamic> list, {double yawOffset = 0}) => [
          for (final s in list)
            GlbLibrary.slot(
                _d((s['pos'] as List)[0]),
                _d((s['pos'] as List)[1]),
                _d((s['pos'] as List)[2]),
                _d(s['yaw']) + yawOffset,
                s['scale'] is List
                    ? vm.Vector3(_d(s['scale'][0], 1), _d(s['scale'][1], 1), _d(s['scale'][2], 1))
                    : null),
        ];
    final bays = slots['yamanoteViaductBays'] as List<dynamic>? ?? const [];
    final bay = GlbLibrary.template(lib.arch, 'YamanoteViaductBay');
    if (bay != null) ref.add(GlbLibrary.instance(bay, mats(bays), name: 'YamanoteViaductBay'));
    final blocks = slots['shopfrontBlocks'] as List<dynamic>? ?? const [];
    for (final kind in ['ShibuyaShopfrontBlockA', 'ShibuyaShopfrontBlockB']) {
      final t = GlbLibrary.template(lib.arch, kind);
      if (t == null) continue;
      ref.add(GlbLibrary.instance(t, mats(blocks.where((b) => b['nodeName'] == kind).toList()),
          name: kind));
    }
  }

  // ----------------------------------------------------- street props
  List<vm.Matrix4> _groundSlots(List<dynamic> list, {double yawOffset = 0, bool roadSign = false}) {
    final out = <vm.Matrix4>[];
    for (final s in list) {
      final p = s['pos'] as List<dynamic>;
      var y = roadSign ? _d(s['groundY'], _d(p[1])) : _d(p[1]);
      final lift = roadSign
          ? (s['onViaduct'] != true && y < 0.3 && !_inScramblePlaza(_d(p[0]), _d(p[2])) && _d(s['lateral']) <= 11.4)
          : (y < 0.3 && !_inScramblePlaza(_d(p[0]), _d(p[2])));
      if (lift) y = 0.18;
      out.add(GlbLibrary.slot(_d(p[0]), y, _d(p[2]), _d(s['yaw']) + yawOffset));
    }
    return out;
  }

  void _streetProps() {
    final props = level.route['streetProps'] as Map<String, dynamic>;
    void inst(String node, List<vm.Matrix4> slots,
        {bool Function(String)? filter,
        fs.Material Function(String, fs.Material)? mat}) {
      final t = GlbLibrary.template(lib.props, node);
      if (t == null) return;
      ref.add(GlbLibrary.instance(t, slots, name: node, filter: filter, materialFor: mat));
    }

    fs.Material emissive(fs.Material m, String hex, double k) {
      final c = GlbLibrary.clonePbr(m)
        ..emissiveFactor = hexColor(hex, k)
        ..emissiveStrength = 1;
      return c;
    }

    inst('TrafficGantry', _groundSlots(props['trafficGantries'] as List, yawOffset: -math.pi / 2),
        mat: (n, m) => switch (n) {
              'Gantry_SignalGreen' => emissive(m, '#22C55E', 3.2),
              'Gantry_SignalAmber' => emissive(m, '#F59E0B', 0.35),
              'Gantry_SignalRed' => emissive(m, '#EF4444', 0.25),
              _ => m,
            });
    inst('AoKanbanSign', _groundSlots(props['roadSigns'] as List, roadSign: true),
        mat: (n, m) => switch (n) {
              'AoKanban_LampLens' => emissive(m, '#FFF4DC', 3),
              'AoKanban_SignFace' => GlbLibrary.clonePbr(m)
                ..baseColorFactor = hexColor('#0052A5')
                ..emissiveFactor = hexColor('#0B5FC0', 0.9),
              _ => m,
            });
    inst('PedestrianRail', _groundSlots(props['pedestrianRails'] as List, yawOffset: -math.pi / 2),
        filter: (n) => n == 'PedRail_PostsAndBars' || n == 'PedRail_TopHandrail');
    inst('StreetLampTokyo', _groundSlots(props['streetLamps'] as List, yawOffset: -math.pi / 2),
        mat: (n, m) => n == 'Lamp_LedLens' ? emissive(m, '#DCEEFF', 4.6) : m);

    // Vending alcoves / transformer poles along the kerbs (the demo's
    // waypoint-stepped placement, 9 m off the centreline).
    final wps = level.waypoints;
    final vend = <vm.Matrix4>[], poles = <vm.Matrix4>[];
    for (int e = 2; e < wps.length - 4; e += 4) {
      final t = wps[e];
      if (t.s < 46 || t.y > 0.3 || _inScramblePlaza(t.x, t.z)) continue;
      final n = wps[math.min(wps.length - 1, e + 1)];
      final rx = n.x - t.x, iz = n.z - t.z;
      final a = math.sqrt(rx * rx + iz * iz);
      if (a < 0.2) continue;
      final o = iz / a, s = -rx / a;
      final c = e % 8 == 2 ? 1.0 : -1.0;
      final f = t.x + o * c * 9, p = t.z + s * c * 9;
      if (_inScramblePlaza(f, p) || world.insideBuilding(f, p, 1.5)) continue;
      final yaw = math.atan2(-o * c, -s * c);
      if (vend.length < 14 && e % 8 == 2) {
        vend.add(GlbLibrary.slot(f, 0.18, p, yaw));
      } else if (poles.length < 14) {
        poles.add(GlbLibrary.slot(f, 0.18, p, yaw));
      }
    }
    inst('VendingAlcove', vend,
        mat: (n, m) => n == 'Vending_Display' ? emissive(m, '#E0F2FE', 2) : m);
    inst('TransformerPole', poles);
  }

  // ---------------------------------------------------------- pin gates
  void _pinGates() {
    for (final g in level.route['pinGates'] as List<dynamic>) {
      final t = GlbLibrary.template(lib.props, 'PinGateArch');
      if (t == null) return;
      final p = g['pos'] as List<dynamic>;
      final sx = (_d(g['postHalfSpan'], 5.6) / 2.65).clamp(1.0, 2.35).toDouble();
      final sy = math.min(math.max(_d(g['clearHeight'], 7.87) / 6.35, 0.95), 1.25);
      t.localTransform = GlbLibrary.slot(
          _d(p[0]), _d(g['groundY'], _d(p[1])), _d(p[2]), _d(g['yaw']), vm.Vector3(sx, sy, 1));
      final glow = _litMaterial(t, 'PinGate_PlasmaTube', (g['color'] as String?) ?? '#4285F4');
      world.pinGates.add(glow);
      ref.add(t);
    }
  }

  GlowProp _litMaterial(fs.Node t, String meshName, String hex) {
    final n = t.getChildByName(meshName);
    final base = hexColor(hex, 0.9);
    final m = n?.mesh != null
        ? GlbLibrary.clonePbr(n!.mesh!.primitives.first.material)
        : fs.PhysicallyBasedMaterial();
    m
      ..emissiveFactor = base
      ..emissiveStrength = 1;
    if (n?.mesh != null) {
      for (final p in n!.mesh!.primitives) {
        p.material = m;
      }
    }
    return GlowProp(m, base, litScale: 3.0);
  }

  // -------------------------------------------------------- boost rings
  void _boostRings() {
    for (final r in level.route['boostRings'] as List<dynamic>) {
      final t = GlbLibrary.template(lib.props, 'NeonBoostRing');
      if (t == null) return;
      final m = r as Map<String, dynamic>;
      final p = m['pos'] as List<dynamic>;
      final y = m['bottomY'] != null
          ? _d(m['bottomY'])
          : (m['groundY'] != null ? _d(m['groundY']) : (_d(p[1]) > 7.8 ? 7.5 : 0.0));
      t.localTransform = GlbLibrary.slot(_d(p[0]), y, _d(p[2]), _d(m['yaw']));
      final glow = _litMaterial(t, 'BoostRing_PlasmaTube', '#38BDF8');
      glow.setLit(true);
      ref.add(t);
      world.rings.add(RingProp(t, glow, m));
    }
  }

  // ------------------------------------------------ neon slide arches
  void _slideArches() {
    for (final r in level.route['slidePortals'] as List<dynamic>) {
      final t = GlbLibrary.template(lib.props, 'NeonSlideArch');
      if (t == null) return;
      final p = r['pos'] as List<dynamic>;
      final jp = r['style'] == 'torii_neon_jp' || r['crestNodeName'] == 'NeonArch_CrestJP';
      t.localTransform = GlbLibrary.slot(
          _d(p[0]), _d(r['groundY'], _d(p[1])), _d(p[2]), _d(r['yaw']) + math.pi);
      t.getChildByName('NeonArch_CrestEN')?.visible = !jp;
      t.getChildByName('NeonArch_CrestJP')?.visible = jp;
      final cyan = _litMaterial(t, 'NeonArch_PlasmaCyan', jp ? '#1E88FF' : '#00D4FF');
      _litMaterial(t, 'NeonArch_PlasmaOrange', jp ? '#FFB300' : '#FF3D00').setLit(true);
      cyan.setLit(true);
      world.slidePortals.add(cyan);
      ref.add(t);
    }
  }
}
