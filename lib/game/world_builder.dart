import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'level_data.dart';
import 'mesh_buf.dart';
import 'route_spline.dart';
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
  GlowProp(this.material, this.baseEmissive, {this.litScale = 2.2});
  final fs.PhysicallyBasedMaterial material;
  final vm.Vector4 baseEmissive;
  final double litScale;
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
  ShibuyaWorld(this.level, this.spline, this.tex);

  final ShibuyaLevel level;
  final RouteSpline spline;
  final WorldTextures tex;

  final fs.Node root = fs.Node(name: 'shibuya_world');
  final List<RingProp> rings = [];
  final List<GlowProp> pinGates = [];
  final List<GlowProp> slidePortals = [];
  final List<GlowProp> googleLetters = [];
  final List<GlowProp> bladeSigns = [];
  late final fs.Node beaconRing;
  late final fs.PhysicallyBasedMaterial beaconMat;

  void build() {
    _ground();
    _buildings();
    _shopfrontsAndSigns();
    _routeDeck();
    _yamanote();
    _grindRails();
    _wallRuns();
    _boostRings();
    _barriers();
    _slidePortals();
    _pinGates();
    _streetLamps();
    _googleTower();
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
    final glass = MeshBuf();
    final roofs = MeshBuf();
    final known = <String>{};
    for (final bd in level.buildings) {
      if (bd['isGoogleHero'] == true) continue;
      final fp = ShibuyaLevel.pts(bd['footprint']);
      final h = (bd['height'] as num).toDouble();
      final style = bd['archStyle'] as String? ?? 'urban_block';
      _prism(style == 'modern_glass_tower' ? glass : walls, roofs, fp, 0, h);
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
      _prism(walls, roofs, fp, 0, h);
    }
    _add(
        walls,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.7, metallic: 0.15)
          ..baseColorTexture = tex.facadeBase
          ..emissiveTexture = tex.facadeGlow
          ..emissiveFactor = vm.Vector4(1.25, 1.25, 1.35, 1),
        'osm_buildings');
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
    const tileW = 7.2; // 8 windows across 7.2 m
    const tileH = 33.6; // 16 floors (2.1 m) per texture tile
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
    final hosts = <String, List<Map<String, dynamic>>>{};
    for (final k in ['bladeSigns', 'wallBillboards']) {
      for (final s in props[k] as List<dynamic>) {
        final m = s as Map<String, dynamic>;
        if (m['hostType'] == 'shopfront' && m['hostId'] != null) {
          hosts.putIfAbsent(m['hostId'] as String, () => []).add(m);
        }
      }
    }
    final walls = MeshBuf();
    final roofs = MeshBuf();
    hosts.forEach((id, signs) {
      // Wall line through the sign wall points, extruded 14 m inward.
      final n = signs.first['wallNormal'] as List<dynamic>;
      final nx = (n[0] as num).toDouble(), nz = (n[2] as num).toDouble();
      final tx = -nz, tz = nx; // along-wall direction
      double minT = 1e9, maxT = -1e9;
      final wp0 = signs.first['wallPoint'] as List<dynamic>;
      final ox = (wp0[0] as num).toDouble(), oz = (wp0[2] as num).toDouble();
      double hostH = 0;
      for (final s in signs) {
        final wp = s['wallPoint'] as List<dynamic>;
        final t = ((wp[0] as num).toDouble() - ox) * tx +
            ((wp[2] as num).toDouble() - oz) * tz;
        minT = math.min(minT, t);
        maxT = math.max(maxT, t);
        hostH = math.max(hostH, (s['hostHeight'] as num?)?.toDouble() ?? 20);
      }
      minT -= 7;
      maxT += 7;
      const depth = 14.0;
      final fp = [
        XZ(ox + tx * minT, oz + tz * minT),
        XZ(ox + tx * maxT, oz + tz * maxT),
        XZ(ox + tx * maxT - nx * depth, oz + tz * maxT - nz * depth),
        XZ(ox + tx * minT - nx * depth, oz + tz * minT - nz * depth),
      ];
      _prism(walls, roofs, fp, 0, hostH);
    });
    _add(
        walls,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.7, metallic: 0.15)
          ..baseColorTexture = tex.facadeBase
          ..emissiveTexture = tex.facadeGlow
          ..emissiveFactor = vm.Vector4(1.35, 1.3, 1.3, 1),
        'shopfronts');
    _add(roofs, pbr(hexColor('#1A2338'), emissive: hexColor('#0D1426')),
        'shopfront_roofs');

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

  // ------------------------------------------------------------ boost rings
  void _boostRings() {
    final geo = fs.TorusGeometry(
        radius: 2.4, tubeRadius: 0.13, radialSegments: 40, tubularSegments: 8);
    for (final r in level.route['boostRings'] as List<dynamic>) {
      final m = r as Map<String, dynamic>;
      final pos = m['pos'] as List<dynamic>;
      final em = hexColor((m['color'] as String?) ?? '#FF4F00', 3.0);
      final mat = pbr(hexColor((m['color'] as String?) ?? '#FF4F00', 0.6),
          emissive: em, roughness: 0.2, metallic: 0.3);
      final node = fs.Node(name: m['id'] as String, mesh: fs.Mesh(geo, mat))
        ..position = w3((pos[0] as num).toDouble(), (pos[1] as num).toDouble(),
            (pos[2] as num).toDouble())
        ..rotation = yawQuat(mirrorYaw((m['yaw'] as num).toDouble()));
      // Torus lies in XZ; stand it up to face along the route.
      node.rotation = node.rotation *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2);
      root.add(node);
      rings.add(RingProp(node, GlowProp(mat, em, litScale: 0.35), m));
    }
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

  // -------------------------------------------------- neon slide arches
  void _slidePortals() {
    for (final p in level.route['slidePortals'] as List<dynamic>) {
      final pos = p['pos'] as List<dynamic>;
      final x = (pos[0] as num).toDouble(), z = (pos[2] as num).toDouble();
      final gy = (p['groundY'] as num?)?.toDouble() ?? 0;
      final half = (p['postHalfSpan'] as num?)?.toDouble() ?? 5.85;
      final top = (p['solidArchTopY'] as num?)?.toDouble() ?? 6.45;
      final bottom = (p['solidArchBottomY'] as num?)?.toDouble() ?? 2.65;
      final laserY = (p['laserTopY'] as num?)?.toDouble() ?? 2.5;
      final yaw = mirrorYaw((p['yaw'] as num).toDouble());
      final c = w3(x, gy, z);
      final frame = MeshBuf();
      final neon = MeshBuf();
      final laser = MeshBuf();
      final cy = math.cos(yaw), sy = math.sin(yaw);
      vm.Vector3 off(double lx, double y) =>
          vm.Vector3(c.x + lx * cy, c.y + y, c.z - lx * sy);
      for (final sd in [-1.0, 1.0]) {
        frame.box(off(sd * half, top / 2), vm.Vector3(0.7, top, 0.7), yaw);
        neon.box(off(sd * (half - 0.4), top / 2), vm.Vector3(0.12, top - 0.6, 0.76), yaw);
      }
      frame.box(off(0, top - 0.4), vm.Vector3(half * 2 + 2.2, 0.8, 0.9), yaw);
      frame.box(off(0, bottom + 0.6), vm.Vector3(half * 2, 0.5, 0.6), yaw);
      neon.box(off(0, top - 0.95), vm.Vector3(half * 2 + 1.6, 0.14, 0.95), yaw);
      neon.box(off(0, bottom + 0.3), vm.Vector3(half * 2 - 0.6, 0.12, 0.66), yaw);
      // laser bar at slide height
      laser.box(off(0, laserY - 0.3), vm.Vector3(half * 2 - 0.8, 0.08, 0.08), yaw);
      laser.box(off(0, laserY - 0.9), vm.Vector3(half * 2 - 0.8, 0.08, 0.08), yaw);
      _add(frame, pbr(hexColor('#111827'), emissive: hexColor('#0B1020'), roughness: 0.4), 'portal_frame');
      final em = hexColor((p['accent'] as String?) ?? '#38BDF8', 2.6);
      final nm = pbr(hexColor((p['accent'] as String?) ?? '#38BDF8', 0.6), emissive: em);
      _add(neon, nm, 'portal_neon');
      final lem = hexColor((p['secondaryAccent'] as String?) ?? '#FF4F00', 3.4);
      final lm = pbr(hexColor('#FF4F00', 0.6), emissive: lem);
      _add(laser, lm, 'portal_laser');
      slidePortals.add(GlowProp(nm, em, litScale: 1.8));
    }
  }

  // -------------------------------------------------------- pin gates
  void _pinGates() {
    for (final g in level.route['pinGates'] as List<dynamic>) {
      final pos = g['pos'] as List<dynamic>;
      final x = (pos[0] as num).toDouble(),
          y = (pos[1] as num).toDouble(),
          z = (pos[2] as num).toDouble();
      final half = (g['postHalfSpan'] as num?)?.toDouble() ?? 5.6;
      final h = (g['clearHeight'] as num?)?.toDouble() ?? 7.87;
      final yaw = mirrorYaw((g['yaw'] as num).toDouble());
      final c = w3(x, y, z);
      final cy = math.cos(yaw), sy = math.sin(yaw);
      vm.Vector3 off(double lx, double yy) =>
          vm.Vector3(c.x + lx * cy, c.y + yy, c.z - lx * sy);
      final frame = MeshBuf();
      final glow = MeshBuf();
      for (final sd in [-1.0, 1.0]) {
        frame.box(off(sd * half, h / 2), vm.Vector3(0.45, h, 0.45), yaw);
        glow.box(off(sd * half, h / 2), vm.Vector3(0.16, h - 0.4, 0.5), yaw);
      }
      frame.box(off(0, h), vm.Vector3(half * 2 + 0.45, 0.5, 0.5), yaw);
      glow.box(off(0, h - 0.12), vm.Vector3(half * 2 - 0.2, 0.12, 0.56), yaw);
      // Street View pin marker above the gate
      glow.box(off(0, h + 1.5), vm.Vector3(1.4, 1.4, 0.35), yaw);
      frame.box(off(0, h + 0.55), vm.Vector3(0.25, 0.9, 0.25), yaw);
      _add(frame, pbr(hexColor('#1E293B'), emissive: hexColor('#0B1020')), 'pin_gate_frame');
      final col = (g['color'] as String?) ?? '#4285F4';
      final em = hexColor(col, 1.4);
      final m = pbr(hexColor(col, 0.6), emissive: em);
      _add(glow, m, 'pin_gate_glow');
      pinGates.add(GlowProp(m, em, litScale: 2.4));
    }
  }

  // ------------------------------------------------------- street lamps
  void _streetLamps() {
    final pole = MeshBuf();
    final lamp = MeshBuf();
    final props = level.route['streetProps'] as Map<String, dynamic>;
    for (final l in props['streetLamps'] as List<dynamic>) {
      final pos = l['pos'] as List<dynamic>;
      final x = (pos[0] as num).toDouble(), z = (pos[2] as num).toDouble();
      final h = (l['height'] as num?)?.toDouble() ?? 7.5;
      final yaw = mirrorYaw((l['yaw'] as num).toDouble());
      pole.box(w3(x, h / 2, z), vm.Vector3(0.18, h, 0.18), yaw);
      lamp.box(w3(x, h, z), vm.Vector3(0.5, 0.2, 1.4), yaw);
    }
    for (final gt in props['trafficGantries'] as List<dynamic>) {
      final pos = gt['pos'] as List<dynamic>;
      final x = (pos[0] as num).toDouble(), z = (pos[2] as num).toDouble();
      final yaw = mirrorYaw((gt['yaw'] as num).toDouble());
      pole.box(w3(x, 3.4, z), vm.Vector3(0.3, 6.8, 0.3), yaw);
      lamp.box(w3(x, 6.6, z), vm.Vector3(0.6, 1.4, 0.4), yaw);
    }
    _add(pole, pbr(hexColor('#334155'), emissive: hexColor('#0F172A'), metallic: 0.6, roughness: 0.4),
        'lamp_poles');
    _add(lamp, pbr(hexColor('#FFF3EC'), emissive: hexColor('#FFE2B8', 3.0)), 'lamp_heads');
  }

  // ------------------------------------------- Shibuya Stream / Google
  void _googleTower() {
    final gt = level.meta['googleTower'] as Map<String, dynamic>;
    final hero = level.buildings.firstWhere((b) => b['isGoogleHero'] == true,
        orElse: () => null);
    final walls = MeshBuf();
    final roofs = MeshBuf();
    if (hero != null) {
      final fp = ShibuyaLevel.pts(hero['footprint']);
      // podium up to the rooftop (22 m) then the tower set back above it
      _prism(walls, roofs, fp, 0, 22);
      double cx = 0, cz = 0;
      for (final q in fp) {
        cx += q.x;
        cz += q.z;
      }
      cx /= fp.length;
      cz /= fp.length;
      final tower = [
        for (final q in fp) XZ(cx + (q.x - cx) * 0.55, cz + (q.z - cz) * 0.55),
      ];
      // offset the tower away from the rooftop beacon so the roof stays open
      final bcn = gt['rooftopBeacon'] as List<dynamic>;
      final bx = (bcn[0] as num).toDouble(), bz = (bcn[2] as num).toDouble();
      final ox = (cx - bx) * 0.35, oz = (cz - bz) * 0.35;
      _prism(walls, roofs,
          [for (final q in tower) XZ(q.x + ox, q.z + oz)], 22,
          (gt['height'] as num).toDouble());
    }
    _add(
        walls,
        pbr(vm.Vector4(1, 1, 1, 1), roughness: 0.25, metallic: 0.55)
          ..baseColorTexture = tex.glassBase
          ..emissiveTexture = tex.glassGlow
          ..emissiveFactor = vm.Vector4(1.2, 1.35, 1.6, 1),
        'google_stream_tower');
    _add(roofs, pbr(hexColor('#1E293B'), emissive: hexColor('#111A2C')), 'google_roof');

    // "Google" sign: six coloured letter blocks on the facade.
    final sc = gt['signCenter'] as List<dynamic>;
    final n = gt['facadeNormal'] as List<dynamic>;
    final nx = (n[0] as num).toDouble(), nz = (n[2] as num).toDouble();
    final tx = -nz, tz = nx;
    final colors = ['#4285F4', '#EA4335', '#FBBC05', '#4285F4', '#34A853', '#EA4335'];
    final yaw = yawFromDir(nx, nz);
    for (int i = 0; i < 6; i++) {
      final off = (i - 2.5) * 3.2;
      final x = (sc[0] as num).toDouble() + tx * off + nx * 0.6;
      final z = (sc[2] as num).toDouble() + tz * off + nz * 0.6;
      final em = hexColor(colors[i], 3.4);
      final m = pbr(hexColor(colors[i], 0.35), emissive: vm.Vector4(0.02, 0.02, 0.03, 1));
      final h = (i == 3) ? 3.6 : (i == 4 ? 3.9 : 2.8);
      root.add(fs.Node(
          name: 'google_letter_$i',
          mesh: fs.Mesh(fs.CuboidGeometry(vm.Vector3(2.3, h, 0.5)), m))
        ..position = w3(x, (sc[1] as num).toDouble(), z)
        ..rotation = yawQuat(yaw));
      googleLetters.add(GlowProp(m, em, litScale: 1.0));
    }

    // Rooftop beacon target ring
    final bcn = gt['rooftopBeacon'] as List<dynamic>;
    beaconMat = pbr(hexColor('#EA4335', 0.6), emissive: hexColor('#EA4335', 2.4));
    beaconRing = fs.Node(
        name: 'rooftop_beacon',
        mesh: fs.Mesh(
            fs.TorusGeometry(radius: 5.5, tubeRadius: 0.16, radialSegments: 48),
            beaconMat))
      ..position = w3((bcn[0] as num).toDouble(), 22.08, (bcn[2] as num).toDouble());
    root.add(beaconRing);
  }
}
