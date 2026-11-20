import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'level_data.dart';
import 'mesh_buf.dart';
import 'route_spline.dart';
import 'world_glb.dart';
import 'world_textures.dart';

vm.Vector4 hexColor(String hex, [double scale = 1.0, double alpha = 1.0]) {
  final h = hex.replaceAll('#', '');
  final v = int.parse(h.substring(0, 6), radix: 16);
  double lin(int c) {
    final s = c / 255.0;
    return s <= 0.04045 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return vm.Vector4(lin((v >> 16) & 255) * scale, lin((v >> 8) & 255) * scale,
      lin(v & 255) * scale, alpha);
}

fs.PhysicallyBasedMaterial pbr(vm.Vector4 base,
    {vm.Vector4? emissive,
    double metallic = 0.0,
    double roughness = 0.6,
    bool doubleSided = true}) {
  final m = fs.PhysicallyBasedMaterial()
    ..baseColorFactor = base
    ..metallicFactor = metallic
    ..roughnessFactor = roughness
    ..doubleSided = doubleSided;
  if (emissive != null) m.emissiveFactor = emissive;
  return m;
}

fs.UnlitMaterial unlit(vm.Vector4 color) => fs.UnlitMaterial()
  ..baseColorFactor = color
  ..doubleSided = true;

/// A neon prop whose glow can be ignited at runtime.
class GlowProp {
  GlowProp(this.material, this.baseEmissive,
      {this.litScale = 2.2, this.letterIndex = -1});
  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 baseEmissive;
  final double litScale;
  final int letterIndex;
  bool lit = false;

  void setLit(bool v, [double pulse = 1.0]) {
    lit = v;
    final k = v ? litScale * pulse : 1.0;
    material.emissiveFactor = vm.Vector4(
        baseEmissive.x * k, baseEmissive.y * k, baseEmissive.z * k, 1);
  }
}

class RingProp {
  RingProp(this.node, this.glow, this.data);
  final fs.Node node;
  final GlowProp glow;
  final Map<String, dynamic> data;
}

/// Static + semi-static 3D content of the Shibuya route, built once from
/// [ShibuyaLevel] data in the reference's coordinates (mirrored via [w3]).
class ShibuyaWorld {
  ShibuyaWorld(this.level, this.spline, this.tex, this.glb);

  final ShibuyaLevel level;
  final RouteSpline spline;
  final WorldTextures tex;
  final GlbLibrary glb;

  final fs.Node root = fs.Node(name: 'shibuya_world');

  /// Holds content placed directly in the demo's right-handed three.js
  /// coordinates (glTF models); mirrors Z into Flutter Scene's view frame.
  final fs.Node refRoot = fs.Node(name: 'ref_frame')
    ..localTransform = vm.Matrix4.diagonal3Values(1, 1, -1);
  late final GlbWorld glbWorld;
  final List<RingProp> rings = [];
  final List<GlowProp> pinGates = [];
  final List<GlowProp> slidePortals = [];
  final List<GlowProp> googleLetters = [];
  final List<GlowProp> bladeSigns = [];
  fs.PhysicallyBasedMaterial? beaconMat;
  final List<List<double>> _footprintBoxes = [];

  void build() {
    root.add(refRoot);
    _ground();
    _buildings();
    _shopfrontsAndSigns();
    _routeDeck();
    _yamanote();
    _grindRails();
    _wallRuns();
    _barriers();
    glbWorld = GlbWorld(this, glb)..build();
  }

  /// Rough footprint test (axis-aligned boxes of the OSM buildings).
  bool insideBuilding(double x, double z, double pad) {
    for (final b in _footprintBoxes) {
      if (x > b[0] - pad && x < b[1] + pad && z > b[2] - pad && z < b[3] + pad) {
        return true;
      }
    }
    return false;
  }

  void _add(MeshBuf b, fs.Material m, [String name = '']) {
    if (b.isEmpty) return;
    root.add(fs.Node(name: name, mesh: fs.Mesh(b.build(), m)));
  }

  // ---------------------------------------------------------------- ground
  void _ground() {
    final b = level.overview['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble();
    final maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble();
    final maxZ = (b['maxZ'] as num).toDouble();
    final buf = MeshBuf();
    final up = vm.Vector3(0, 1, 0);
    buf.quad(w3(minX, 0, minZ), w3(maxX, 0, minZ), w3(maxX, 0, maxZ),
        w3(minX, 0, maxZ), up,
        u0: 0, v0: 0, u1: 1, v1: 1);
    final mat = pbr(vm.Vector4(0.6, 0.6, 0.6, 1), roughness: 0.55, metallic: 0.1)
      ..baseColorTexture = tex.ground
      ..emissiveTexture = tex.ground
      ..emissiveFactor = vm.Vector4(0.55, 0.6, 0.7, 1);
    _add(buf, mat, 'maps_ground');

    // Outer dark apron beyond the mapped area.
    final apron = MeshBuf();
    apron.quad(w3(-2000, -0.05, -2000), w3(2000, -0.05, -2000),
        w3(2000, -0.05, 2000), w3(-2000, -0.05, 2000), up);
    _add(apron, pbr(hexColor('#0E141F'), emissive: hexColor('#0B111C')), 'apron');
  }

  // ------------------------------------------------------------- buildings
  void _buildings() {
    final walls = MeshBuf();
    final brick = MeshBuf();
    final glass = MeshBuf();
    final roofs = MeshBuf();
    final known = <String>{};
    final pick = math.Random(1335178864);
    for (final bd in level.buildings) {
      final fp = ShibuyaLevel.pts(bd['footprint']);
      known.add('${fp.first.x.toStringAsFixed(1)},${fp.first.z.toStringAsFixed(1)}');
      if (bd['isGoogleHero'] == true || bd['replacedByHeroArch'] == true) continue;
      _footprintBoxes.add([
        fp.map((q) => q.x).reduce(math.min),
        fp.map((q) => q.x).reduce(math.max),
        fp.map((q) => q.z).reduce(math.min),
        fp.map((q) => q.z).reduce(math.max),
      ]);
      final h = (bd['height'] as num).toDouble();
      final style = bd['archStyle'] as String? ?? 'urban_block';
      final target = style == 'modern_glass_tower'
          ? glass
          : (style == 'urban_block' && pick.nextDouble() < 0.55 ? brick : walls);
      _prism(target, roofs, fp, 0, h);
      if (style != 'modern_glass_tower') _storefronts(fp);
      known.add('${fp.first.x.toStringAsFixed(1)},${fp.first.z.toStringAsFixed(1)}');
    }
    // Remaining overview footprints (no OSM height): low/mid blocks.
    final rng = math.Random(14598366);
    for (final poly in level.overview['buildings'] as List<dynamic>) {
      final fp = ShibuyaLevel.pts(poly);
      if (fp.length < 3) continue;
      final key = '${fp.first.x.toStringAsFixed(1)},${fp.first.z.toStringAsFixed(1)}';
      if (known.contains(key)) continue;
      double cx = 0, cz = 0;
      for (final q in fp) {
        cx += q.x;
        cz += q.z;
      }
      cx /= fp.length;
      cz /= fp.length;
      // Keep the route corridor clear of guessed geometry.
      if (_distToRoute(cx, cz) < 16) continue;
      final h = 12.0 + rng.nextDouble() * 26.0;
      _prism(rng.nextDouble() < 0.4 ? brick : walls, roofs, fp, 0, h);
    }
    _add(
        walls,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.7, metallic: 0.15)
          ..baseColorTexture = tex.facadeBase
          ..emissiveTexture = tex.facadeGlow
          ..emissiveFactor = vm.Vector4(1.0, 1.0, 1.1, 1),
        'osm_buildings');
    _add(
        brick,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.85, metallic: 0.05)
          ..baseColorTexture = tex.brickBase
          ..emissiveTexture = tex.brickGlow
          ..emissiveFactor = vm.Vector4(1.0, 0.95, 0.9, 1),
        'osm_brick_buildings');
    _flushStorefronts();
    _add(
        glass,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.25, metallic: 0.55)
          ..baseColorTexture = tex.glassBase
          ..emissiveTexture = tex.glassGlow
          ..emissiveFactor = vm.Vector4(1.3, 1.3, 1.45, 1),
        'osm_glass_towers');
    _add(roofs, pbr(hexColor('#1A2338'), emissive: hexColor('#0D1426'), roughness: 0.8),
        'osm_roofs');
  }

  final MeshBuf _shops = MeshBuf();

  /// Warm ground-floor shopfront band on walls facing within 40 m of the route.
  void _storefronts(List<XZ> fp) {
    final pts = List<XZ>.from(fp);
    double area = 0;
    for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      area += pts[j].x * pts[i].z - pts[i].x * pts[j].z;
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    for (int i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final dx = b.x - a.x, dz = b.z - a.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 3) continue;
      final mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2;
      if (_distToRoute(mx, mz) > 40) continue;
      final nx = dz / len * sign, nz = -dx / len * sign;
      const off = 0.06;
      final n = vm.Vector3(-nx, 0, nz);
      _shops.quad(
          w3(a.x + nx * off, 0.2, a.z + nz * off),
          w3(b.x + nx * off, 0.2, b.z + nz * off),
          w3(b.x + nx * off, 3.6, b.z + nz * off),
          w3(a.x + nx * off, 3.6, a.z + nz * off),
          n,
          u0: 0,
          u1: len / 7.0,
          v0: 1,
          v1: 0);
    }
  }

  void _flushStorefronts() {
    _add(
        _shops,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.3, metallic: 0.2)
          ..baseColorTexture = tex.shopBase
          ..emissiveTexture = tex.shopGlow
          ..emissiveFactor = vm.Vector4(1.6, 1.4, 1.2, 1),
        'storefronts');
  }

  double _distToRoute(double x, double z) {
    double best = 1e9;
    for (final w in spline.waypoints) {
      final d = (w.x - x) * (w.x - x) + (w.z - z) * (w.z - z);
      if (d < best) best = d;
    }
    return math.sqrt(best);
  }

  /// Extrudes a footprint into walls (UV-tiled windows) and a flat roof.
  void _prism(MeshBuf walls, MeshBuf roofs, List<XZ> fp, double y0, double y1) {
    final pts = List<XZ>.from(fp);
    if (pts.length > 3 &&
        (pts.first.x - pts.last.x).abs() < 1e-3 &&
        (pts.first.z - pts.last.z).abs() < 1e-3) {
      pts.removeLast();
    }
    if (pts.length < 3) return;
    // Signed area to orient outward normals.
    double area = 0;
    for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      area += pts[j].x * pts[i].z - pts[i].x * pts[j].z;
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    double u = 0;
    const tileW = 5.6; // 8 windows across 5.6 m
    const tileH = 28.8; // 16 floors (1.8 m) per texture tile
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      final dx = b.x - a.x, dz = b.z - a.z;
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 0.05) continue;
      // outward normal in reference frame, then mirror z
      final nx = dz / len * sign, nz = -dx / len * sign;
      final n = vm.Vector3(-nx, 0, nz);
      walls.quad(w3(a.x, y0, a.z), w3(b.x, y0, b.z), w3(b.x, y1, b.z),
          w3(a.x, y1, a.z), n,
          u0: u / tileW,
          u1: (u + len) / tileW,
          v0: 1 - y0 / tileH,
          v1: 1 - y1 / tileH);
      u += len;
    }
    final flat = <double>[for (final q in pts) ...[q.x, q.z]];
    final tris = triangulatePolygon(flat);
    final base = roofs.vertexCount;
    final up = vm.Vector3(0, 1, 0);
    for (final q in pts) {
      roofs.vertex(w3(q.x, y1, q.z), up, q.x / 20, q.z / 20);
    }
    for (int i = 0; i + 2 < tris.length; i += 3) {
      roofs.tri(base + tris[i], base + tris[i + 1], base + tris[i + 2]);
    }
  }

  // ---------------------------------------- shopfronts hosting neon signs
  void _shopfrontsAndSigns() {
    final props = level.route['streetProps'] as Map<String, dynamic>;


    // Neon blade signs & billboards, grouped by accent colour.
    final byAccent = <String, MeshBuf>{};
    final dark = MeshBuf();
    for (final k in ['bladeSigns', 'wallBillboards']) {
      for (final s in props[k] as List<dynamic>) {
        final m = s as Map<String, dynamic>;
        final pos = m['pos'] as List<dynamic>;
        final x = (pos[0] as num).toDouble(),
            y = (pos[1] as num).toDouble(),
            z = (pos[2] as num).toDouble();
        final yaw = mirrorYaw((m['yaw'] as num).toDouble());
        final wdt = (m['width'] as num).toDouble();
        final hgt = (m['height'] as num).toDouble();
        final accent = (m['accent'] as String?) ?? '#FF4F00';
        final buf = byAccent.putIfAbsent(accent, () => MeshBuf());
        if (k == 'bladeSigns') {
          // vertical blade sticking out of the wall
          dark.box(w3(x, y, z), vm.Vector3(0.32, hgt, wdt), yaw);
          buf.box(w3(x, y, z), vm.Vector3(0.40, hgt * 0.86, wdt * 0.82), yaw);
        } else {
          dark.box(w3(x, y, z), vm.Vector3(wdt + 0.4, hgt + 0.4, 0.3), yaw);
          buf.box(w3(x, y, z), vm.Vector3(wdt, hgt, 0.42), yaw);
        }
      }
    }
    _add(dark, pbr(hexColor('#0B1020'), roughness: 0.4), 'sign_frames');
    byAccent.forEach((accent, buf) {
      final em = hexColor(accent, 2.4);
      final mat = pbr(hexColor(accent, 0.6), emissive: em, roughness: 0.3);
      bladeSigns.add(GlowProp(mat, em, litScale: 1.6));
      _add(buf, mat, 'neon_signs_$accent');
    });
  }

  // ------------------------------------------------- route deck & viaduct
  void _routeDeck() {
    final deck = MeshBuf();
    final sides = MeshBuf();
    final piers = MeshBuf();
    final edge = MeshBuf();
    final s = RouteSample();
    double lastPier = -100;
    for (double d = 0; d < spline.length; d += 2.0) {
      final a = spline.sample(d, RouteSample());
      spline.sample(math.min(spline.length, d + 2.0), s);
      if (a.y < 0.25 && s.y < 0.25) continue;
      final hwA = a.halfWidth, hwB = s.halfWidth;
      vm.Vector3 pa(double lat, double dy) =>
          w3(a.x + a.rx * lat, a.y + dy, a.z + a.rz * lat);
      vm.Vector3 pb(double lat, double dy) =>
          w3(s.x + s.rx * lat, s.y + dy, s.z + s.rz * lat);
      final up = vm.Vector3(0, 1, 0);
      deck.quad(pa(-hwA, 0), pa(hwA, 0), pb(hwB, 0), pb(-hwB, 0), up,
          u0: 0, u1: 1, v0: d / 8, v1: (d + 2) / 8);
      // deck slab sides
      for (final side in [-1.0, 1.0]) {
        final n = w3(a.rx * side, 0, a.rz * side);
        sides.quad(pa(side * hwA, 0), pb(side * hwB, 0), pb(side * hwB, -1.4),
            pa(side * hwA, -1.4), n);
        // parapet neon edge strip
        edge.quad(pa(side * (hwA - 0.1), 0.9), pb(side * (hwB - 0.1), 0.9),
            pb(side * (hwB - 0.1), 1.05), pa(side * (hwA - 0.1), 1.05), n);
        sides.quad(pa(side * hwA, 0), pb(side * hwB, 0), pb(side * hwB, 0.9),
            pa(side * hwA, 0.9), n);
      }
      if (d - lastPier >= 12 && a.y > 2.0) {
        lastPier = d;
        for (final side in [-1.0, 1.0]) {
          final lat = side * (hwA - 1.2);
          piers.box(w3(a.x + a.rx * lat, a.y * 0.5 - 0.7, a.z + a.rz * lat),
              vm.Vector3(1.1, a.y - 1.4, 1.1), mirrorYaw(a.yaw));
        }
      }
    }
    _add(deck, pbr(hexColor('#2A3446'), emissive: hexColor('#141B28'), roughness: 0.5, metallic: 0.2),
        'viaduct_deck');
    _add(sides, pbr(hexColor('#1C2434'), emissive: hexColor('#0E1420'), roughness: 0.6), 'viaduct_sides');
    _add(piers, pbr(hexColor('#232C3D'), emissive: hexColor('#0E1420'), roughness: 0.7), 'viaduct_piers');
    _add(edge, pbr(hexColor('#38BDF8', 0.5), emissive: hexColor('#38BDF8', 1.6)), 'viaduct_edge');

    // Lane dashes along the whole route.
    final dashes = MeshBuf();
    for (double d = 4; d < spline.length - 4; d += 9) {
      final a = spline.sample(d, RouteSample());
      for (final lat in [-1.8, 1.8]) {
        final x = a.x + a.rx * lat, z = a.z + a.rz * lat;
        dashes.box(w3(x, a.y + 0.03, z), vm.Vector3(0.14, 0.02, 3.0),
            mirrorYaw(a.yaw));
      }
    }
    _add(dashes, unlit(vm.Vector4(0.55, 0.62, 0.75, 1)), 'lane_dashes');
  }

  // -------------------------------------------------------- Yamanote line
  void _yamanote() {
    final tracks = level.meta['yamanoteTracks'] as Map<String, dynamic>;
    final rails = MeshBuf();
    final deck = MeshBuf();
    for (final key in ['outer', 'inner']) {
      final pts = [
        for (final p in tracks[key] as List<dynamic>)
          vm.Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
              (p[2] as num).toDouble()),
      ];
      for (int i = 0; i + 1 < pts.length; i++) {
        final a = pts[i], b = pts[i + 1];
        final dx = b.x - a.x, dz = b.z - a.z;
        final len = math.sqrt(dx * dx + dz * dz);
        final rx = -dz / len, rz = dx / len;
        for (final g in [-0.72, 0.72]) {
          rails.quad(
              w3(a.x + rx * (g - 0.06), a.y + 0.25, a.z + rz * (g - 0.06)),
              w3(b.x + rx * (g - 0.06), b.y + 0.25, b.z + rz * (g - 0.06)),
              w3(b.x + rx * (g + 0.06), b.y + 0.25, b.z + rz * (g + 0.06)),
              w3(a.x + rx * (g + 0.06), a.y + 0.25, a.z + rz * (g + 0.06)),
              vm.Vector3(0, 1, 0));
        }
        deck.quad(
            w3(a.x - rx * 2.4, a.y, a.z - rz * 2.4),
            w3(b.x - rx * 2.4, b.y, b.z - rz * 2.4),
            w3(b.x + rx * 2.4, b.y, b.z + rz * 2.4),
            w3(a.x + rx * 2.4, a.y, a.z + rz * 2.4),
            vm.Vector3(0, 1, 0));
      }
    }
    _add(deck, pbr(hexColor('#1F2737'), emissive: hexColor('#10161F')), 'yamanote_deck');
    _add(rails, pbr(hexColor('#34A853', 0.5), emissive: hexColor('#34A853', 1.8)),
        'yamanote_rails');
  }

  // ------------------------------------------------------------ grind rails
  void _grindRails() {
    final rails = MeshBuf();
    final hero = MeshBuf();
    final posts = MeshBuf();
    for (final r in level.route['grindRails'] as List<dynamic>) {
      final pts = [
        for (final p in r['points'] as List<dynamic>)
          w3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
              (p[2] as num).toDouble()),
      ];
      final isHero = r['heroRailLaunch'] == true;
      final radius = isHero ? 0.14 : 0.105;
      _tube(isHero ? hero : rails, pts, radius);
      for (final p in (r['posts'] as List<dynamic>? ?? const [])) {
        final x = (p['x'] as num).toDouble(), z = (p['z'] as num).toDouble();
        final yb = (p['yBase'] as num?)?.toDouble() ?? 0;
        final yt = (p['yTop'] as num?)?.toDouble() ?? 4;
        posts.box(w3(x, (yb + yt) / 2, z), vm.Vector3(0.22, yt - yb, 0.22), 0);
        if (p['cantilevered'] == true && p['railX'] != null) {
          final rx = (p['railX'] as num).toDouble(),
              rz = (p['railZ'] as num).toDouble();
          final mid = w3((x + rx) / 2, yt - 0.08, (z + rz) / 2);
          final len = math.sqrt((rx - x) * (rx - x) + (rz - z) * (rz - z));
          posts.box(mid, vm.Vector3(0.14, 0.14, len),
              yawFromDir(rx - x, rz - z));
        }
      }
    }
    _add(rails, pbr(hexColor('#FF4F00', 0.6), emissive: hexColor('#FF6A1F', 3.2), metallic: 0.6, roughness: 0.25),
        'grind_rails');
    _add(hero, pbr(hexColor('#4285F4', 0.6), emissive: hexColor('#7BAAF7', 3.2), metallic: 0.6, roughness: 0.25),
        'hero_rail');
    _add(posts, pbr(hexColor('#2E3747'), emissive: hexColor('#121822'), metallic: 0.5, roughness: 0.4),
        'rail_posts');
  }

  void _tube(MeshBuf buf, List<vm.Vector3> pts, double r, {int sides = 8}) {
    // densify with Catmull-Rom for smooth bends
    final dense = <vm.Vector3>[];
    for (int i = 0; i + 1 < pts.length; i++) {
      final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      for (int k = 0; k < 4; k++) {
        final t = k / 4;
        final t2 = t * t, t3 = t2 * t;
        dense.add((p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
            0.5);
      }
    }
    dense.add(pts.last);
    vm.Vector3 prevN = vm.Vector3(0, 1, 0);
    final rings = <List<int>>[];
    for (int i = 0; i < dense.length; i++) {
      final t = (dense[math.min(dense.length - 1, i + 1)] -
              dense[math.max(0, i - 1)])
          .normalized();
      var side = t.cross(prevN);
      if (side.length2 < 1e-6) side = t.cross(vm.Vector3(1, 0, 0));
      side.normalize();
      final nrm = side.cross(t).normalized();
      prevN = nrm;
      final ring = <int>[];
      for (int k = 0; k < sides; k++) {
        final a = k / sides * math.pi * 2;
        final dir = nrm * math.cos(a) + side * math.sin(a);
        ring.add(buf.vertex(dense[i] + dir * r, dir, k / sides, i / 4));
      }
      rings.add(ring);
    }
    for (int i = 0; i + 1 < rings.length; i++) {
      for (int k = 0; k < sides; k++) {
        final a = rings[i][k], b = rings[i][(k + 1) % sides];
        final c = rings[i + 1][(k + 1) % sides], d = rings[i + 1][k];
        buf.tri(a, b, c);
        buf.tri(a, c, d);
      }
    }
  }

  // ------------------------------------------------------------- wall runs
  void _wallRuns() {
    final panels = MeshBuf();
    final frame = MeshBuf();
    for (final wr in level.route['wallRuns'] as List<dynamic>) {
      final pts = ShibuyaLevel.pts([
        for (final p in wr['points'] as List<dynamic>) [p[0], p[2]],
      ]);
      final y = ((wr['points'] as List<dynamic>).first[1] as num).toDouble();
      final h = (wr['height'] as num?)?.toDouble() ?? 4.6;
      final nrm = wr['normal'] as List<dynamic>;
      final n = vm.Vector3((nrm[0] as num).toDouble(), 0, -(nrm[2] as num).toDouble());
      for (int i = 0; i + 1 < pts.length; i++) {
        final a = pts[i], b = pts[i + 1];
        panels.quad(w3(a.x, y - h / 2 + 0.3, a.z), w3(b.x, y - h / 2 + 0.3, b.z),
            w3(b.x, y + h / 2, b.z), w3(a.x, y + h / 2, a.z), n);
        frame.quad(w3(a.x, y + h / 2, a.z), w3(b.x, y + h / 2, b.z),
            w3(b.x, y + h / 2 + 0.18, b.z), w3(a.x, y + h / 2 + 0.18, a.z), n);
        frame.quad(w3(a.x, y - h / 2 + 0.12, a.z), w3(b.x, y - h / 2 + 0.12, b.z),
            w3(b.x, y - h / 2 + 0.3, b.z), w3(a.x, y - h / 2 + 0.3, a.z), n);
      }
    }
    final glass = pbr(hexColor('#38BDF8', 0.35, 0.55),
        emissive: hexColor('#38BDF8', 0.9), roughness: 0.15)
      ..alphaMode = fs.AlphaMode.blend;
    _add(panels, glass, 'wall_run_panels');
    _add(frame, pbr(hexColor('#38BDF8', 0.5), emissive: hexColor('#7DD3FC', 3.0)),
        'wall_run_frames');
  }


  // ---------------------------------------------------------- barriers
  void _barriers() {
    final body = MeshBuf();
    final stripe = MeshBuf();
    for (final b in level.route['streetBarriers'] as List<dynamic>) {
      final pos = b['pos'] as List<dynamic>;
      final x = (pos[0] as num).toDouble(), z = (pos[2] as num).toDouble();
      final gy = (b['groundY'] as num?)?.toDouble() ?? 0;
      final wdt = (b['width'] as num?)?.toDouble() ?? 2.8;
      final hgt = (b['height'] as num?)?.toDouble() ?? 1.15;
      final dep = (b['depth'] as num?)?.toDouble() ?? 0.9;
      final yaw = mirrorYaw((b['yaw'] as num).toDouble());
      body.box(w3(x, gy + hgt / 2, z), vm.Vector3(wdt, hgt, dep), yaw);
      for (int i = 0; i < 2; i++) {
        stripe.box(w3(x, gy + hgt * (0.35 + i * 0.4), z),
            vm.Vector3(wdt + 0.02, hgt * 0.14, dep + 0.02), yaw);
      }
    }
    _add(body, pbr(hexColor('#E2E8F0', 0.7), emissive: hexColor('#94A3B8', 0.25), roughness: 0.5),
        'barrier_body');
    _add(stripe, pbr(hexColor('#FF4F00', 0.6), emissive: hexColor('#FF4F00', 2.6)),
        'barrier_stripes');
  }




}
