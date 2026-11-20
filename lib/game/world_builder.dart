import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'glb_library.dart';
import 'level_data.dart';
import 'mesh_buf.dart';
import 'osm_city.dart';
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
  /// One material per grind rail (index = route grindRails order).
  final List<fs.PhysicallyBasedMaterial> railMats = [];
  fs.PhysicallyBasedMaterial? beaconMat;
  final List<List<double>> _footprintBoxes = [];

  void build() {
    root.add(refRoot);
    _ground();
    _grindRails();
    _wallRuns();
    _barriers();
    _distantSkyline();
    glbWorld = GlbWorld(this, glb)..build();
  }

  /// Builds the OSM city (async: paints the facade textures).
  Future<void> buildCity() async {
    final city = OsmCity(this);
    await city.build();
    _footprintBoxes.addAll(city.bounds);
  }

  /// Photo-camera colliders: [minX,maxX,minY,maxY,minZ,maxZ] (demo's
  /// `_photoColliders`), from the OSM city plus the hero arch boxes.
  List<List<double>> get photoColliders => [
        for (final b in _footprintBoxes)
          [b[0], b[1], 0.0, b.length > 4 ? b[4] : 30.0, b[2], b[3]],
        [209, 260, 0, 182, 254, 295],
        [223, 269, 0, 22.1, 237, 262],
        ...glbWorld.colliders,
      ];

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
  late final fs.PhysicallyBasedMaterial mapsOverlayMat;
  late final fs.Node mapsOverlay;
  final List<fs.Node> dropPin = [];

  bool inScramblePlaza(double x, double z) {
    final sc = level.meta['scrambleCrossing'] as Map<String, dynamic>;
    final c = sc['center'] as List<dynamic>;
    final r = (sc['radius'] as num).toDouble();
    final dx = x - (c[0] as num).toDouble(), dz = z - (c[2] as num).toDouble();
    return dx * dx + dz * dz < r * r;
  }

  void _ground() {
    final up = vm.Vector3(0, 1, 0);
    // ShibuyaMirrorWetAsphalt: 1180 m dark slate tarmac (#111C2D).
    final asphalt = MeshBuf();
    asphalt.quad(w3(-590, 0, -590), w3(590, 0, -590), w3(590, 0, 590),
        w3(-590, 0, 590), up);
    _add(asphalt,
        pbr(hexColor('#111C2D'), emissive: hexColor('#08101E', 0.24), roughness: 0.42, metallic: 0.06),
        'ShibuyaMirrorWetAsphalt');

    // DarkModeGoogleMapsGround overlay; fades out during the sky drop.
    final b = level.overview['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble();
    final maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble();
    final maxZ = (b['maxZ'] as num).toDouble();
    final buf = MeshBuf();
    buf.quad(w3(minX, 0.055, minZ), w3(maxX, 0.055, minZ), w3(maxX, 0.055, maxZ),
        w3(minX, 0.055, maxZ), up,
        u0: 0, v0: 0, u1: 1, v1: 1);
    mapsOverlayMat = fs.PhysicallyBasedMaterial(baseColorTexture: tex.ground, emissiveTexture: tex.ground)
      ..baseColorFactor = vm.Vector4(0, 0, 0, 1)
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..alphaMode = fs.AlphaMode.blend
      ..doubleSided = true;
    mapsOverlay = fs.Node(name: 'maps_overlay', mesh: fs.Mesh(buf.build(), mapsOverlayMat));
    root.add(mapsOverlay);

    // Google Maps drop-pin rings at the start waypoint.
    final w0 = level.waypoints.first;
    fs.Node ring(double r0, double r1, String hex, double op, double y) {
      final g = r0 <= 0
          ? fs.DiscGeometry(radius: r1, segments: 64)
          : fs.RingGeometry(innerRadius: r0, outerRadius: r1, segments: 64);
      final m = fs.UnlitMaterial()
        ..baseColorFactor = hexColor(hex, 1, op)
        ..alphaMode = fs.AlphaMode.blend
        ..doubleSided = true;
      final n = fs.Node(mesh: fs.Mesh(g, m))..position = w3(w0.x, y, w0.z);
      root.add(n);
      dropPin.add(n);
      return n;
    }

    ring(0, 10.5, '#FBBC05', 0.22, 0.095);
    ring(9.2, 10.6, '#FBBC05', 0.96, 0.096);
    ring(10.8, 11.6, '#FDE68A', 0.56, 0.097);
    ring(0, 3.4, '#FF4F00', 0.98, 0.098);
    ring(3.4, 4.0, '#FFFFFF', 0.92, 0.099);

    _sidewalksAndMarkings();
  }

  /// `_buildGraniteSidewalks` + `_buildScrambleCrosswalks` (road paint).
  void _sidewalksAndMarkings() {
    final wps = level.waypoints;
    final side = MeshBuf();
    final paint = MeshBuf();
    const n = 7.25, r = 4.4, i = 0.18, a = 0.24;
    for (int o = 0; o < wps.length - 1; o++) {
      final s0 = wps[o], c = wps[o + 1];
      if (s0.y > 0.25 || c.y > 0.25) continue;
      final l = (s0.x + c.x) * 0.5, u = (s0.z + c.z) * 0.5;
      if (inScramblePlaza(l, u) || (l > 230 && u > 205)) continue;
      final dx = c.x - s0.x, dz = c.z - s0.z;
      final p = math.sqrt(dx * dx + dz * dz);
      if (p < 0.8) continue;
      final m = dx / p, h = dz / p, g = -h, gz = m;
      final yaw = mirrorYaw(math.atan2(m, h));
      final y = p + 0.85;
      for (final e in [-1.0, 1.0]) {
        final ox = l + g * e * 9.45, oz = u + gz * e * 9.45;
        if (inScramblePlaza(ox, oz)) continue;
        side.box(w3(ox, i * 0.5, oz), vm.Vector3(r, i, y), yaw);
        final fx = l + g * e * (n - a * 0.35), fz = u + gz * e * (n - a * 0.35);
        side.box(w3(fx, i * 0.42, fz), vm.Vector3(a, i * 0.84, y), yaw);
      }
    }
    _add(side, pbr(hexColor('#1E2736'), roughness: 0.78, metallic: 0.06, emissive: hexColor('#0A101A')),
        'ShibuyaGraniteSidewalks');

    void flat(double x, double z, double w, double len, double yawRef, [double y = 0.025]) {
      paint.box(w3(x, y, z), vm.Vector3(w, 0.004, len), mirrorYaw(yawRef));
    }

    // Scramble crosswalk stripes.
    for (final cw in level.streets['crosswalks'] as List<dynamic>) {
      final st = cw['start'] as List<dynamic>, en = cw['end'] as List<dynamic>;
      final ax = (st[0] as num).toDouble(), az = (st[1] as num).toDouble();
      final sx = (en[0] as num).toDouble() - ax, sz = (en[1] as num).toDouble() - az;
      final len = math.sqrt(sx * sx + sz * sz);
      if (len < 1.5) continue;
      final ux = sx / len, uz = sz / len;
      final w = ((cw['width'] as num?)?.toDouble() ?? 8).clamp(3.5, 10.5);
      final cnt = (cw['stripeCount'] as num?)?.toInt() ?? math.max(4, (len / 1.65).floor());
      final g = (len / math.max(1, cnt) * 0.48).clamp(0.56, 0.9);
      final yaw = math.atan2(ux, uz);
      for (int e = 0; e < cnt; e++) {
        final t = (e + 0.5) / cnt;
        // stripe: width w across the walk, depth g along it
        paint.box(w3(ax + sx * t, 0.025, az + sz * t), vm.Vector3(w, 0.004, g),
            mirrorYaw(yaw));
      }
    }
    // Lane dashes (±1.8) and edge lines (±5.4) every 7.5 m along the route.
    double acc = 0;
    for (int e = 0; e < wps.length - 1; e++) {
      final p0 = wps[e], p1 = wps[e + 1];
      if (p0.y > 0.25 || p1.y > 0.25) continue;
      final dx = p1.x - p0.x, dz = p1.z - p0.z;
      final c = math.sqrt(dx * dx + dz * dz);
      if (c < 0.5) continue;
      final l = dx / c, u = dz / c, d = -u, f = l, yaw = math.atan2(l, u);
      for (double k = 0; k < c; k += 1.5) {
        acc += 1.5;
        if (acc < 7.5) continue;
        acc = 0;
        final rx = p0.x + l * k, rz = p0.z + u * k;
        if (inScramblePlaza(rx, rz)) continue;
        for (final o in [-1.8, 1.8, -5.4, 5.4]) {
          final edge = o.abs() > 4;
          flat(rx + d * o, rz + f * o, edge ? 0.16 : 0.18, edge ? 4.4 : 2.6, yaw, 0.022);
        }
      }
    }
    // Lane arrows every 40 m, stop bars every 95 m.
    double o = 0, sb = 0;
    for (int e = 0; e < wps.length - 1; e++) {
      final p0 = wps[e], p1 = wps[e + 1];
      if (p0.y > 0.25 || p1.y > 0.25) continue;
      final dx = p1.x - p0.x, dz = p1.z - p0.z;
      final u = math.sqrt(dx * dx + dz * dz);
      if (u < 0.8) continue;
      final d = dx / u, f = dz / u, px = -f, pz = d, yaw = math.atan2(d, f);
      o += u;
      sb += u;
      final gx = (p0.x + p1.x) * 0.5, gz = (p0.z + p1.z) * 0.5;
      if (inScramblePlaza(gx, gz)) continue;
      if (o >= 40) {
        o = 0;
        for (final lat in [-3.6, 0.0, 3.6]) {
          final ax = gx + px * lat, az = gz + pz * lat;
          const k = 0.96;
          flat(ax - d * 0.55 * k, az - f * 0.55 * k, 0.32 * k, 2.55 * k, yaw, 0.024);
          // arrow head (approximated by a short wide bar + tip)
          flat(ax + d * 1.0 * k, az + f * 1.0 * k, 1.1 * k, 0.5 * k, yaw, 0.024);
          flat(ax + d * 1.45 * k, az + f * 1.45 * k, 0.55 * k, 0.45 * k, yaw, 0.024);
        }
      }
      if (sb >= 95) {
        sb = 0;
        flat(gx, gz, 10.8, 0.46, yaw, 0.023);
      }
    }
    _add(paint, pbr(hexColor('#DCE4EE'), emissive: hexColor('#1A2438', 0.12), roughness: 0.34, metallic: 0.04),
        'ScrambleCrosswalksSAT');
  }



  /// Warm ground-floor shopfront band on walls facing within 40 m of the route.



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




  // ------------------------------------------------------------ grind rails
  void _grindRails() {
    final posts = MeshBuf();
    for (final r in level.route['grindRails'] as List<dynamic>) {
      final pts = [
        for (final p in r['points'] as List<dynamic>)
          w3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
              (p[2] as num).toDouble()),
      ];
      final isHero = r['heroRailLaunch'] == true;
      final radius = isHero ? 0.14 : 0.105;
      final rb = MeshBuf();
      _tube(rb, pts, radius * 1.06);
      final rm = pbr(isHero ? hexColor('#38BDF8') : hexColor('#2E405E'),
          emissive: isHero ? hexColor('#38BDF8', 1.55) : hexColor('#FF4F00', 0.72),
          metallic: 0.72, roughness: 0.18);
      railMats.add(rm);
      _add(rb, rm, 'GrindRail_${r['id']}');
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
    _add(posts, pbr(hexColor('#334155'), metallic: 0.78, roughness: 0.42),
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
    // _buildWallRunsAndTransferArcs: 0.18 m chevron panels (Lg texture),
    // centre at y + h*0.46, height h*0.78, plus support pylons.
    final panels = MeshBuf();
    final pylons = MeshBuf();
    for (final wr in level.route['wallRuns'] as List<dynamic>) {
      final a = wr['points'] as List<dynamic>;
      final sH = (wr['height'] as num?)?.toDouble() ?? 5.4;
      for (int e = 0; e + 1 < a.length; e++) {
        final t = a[e], n = a[e + 1];
        double v(dynamic x) => (x as num).toDouble();
        final ix = v(n[0]) - v(t[0]), cz = v(n[2]) - v(t[2]);
        final l = math.sqrt(ix * ix + cz * cz);
        if (l < 0.2) continue;
        final u = math.atan2(ix, cz);
        final dx = (v(t[0]) + v(n[0])) * 0.5, fy = (v(t[1]) + v(n[1])) * 0.5 + sH * 0.46;
        final pz = (v(t[2]) + v(n[2])) * 0.5;
        // two big faces with u running along the wall (repeat every 10 m)
        final hw = 0.09, hh = sH * 0.39, hl = (l + 0.15) / 2;
        final ca = math.cos(u), sa = math.sin(u);
        vm.Vector3 p(double lx, double ly, double lz) =>
            vm.Vector3(dx + lx * ca + lz * sa, fy + ly, pz - lx * sa + lz * ca);
        for (final sd in [-1.0, 1.0]) {
          final nrm = vm.Vector3(sd * ca, 0, -sd * sa);
          panels.quad(p(sd * hw, -hh, -hl), p(sd * hw, -hh, hl), p(sd * hw, hh, hl), p(sd * hw, hh, -hl),
              nrm, u0: 0, u1: l / 10, v0: 1, v1: 0);
        }
        if (e % 2 == 0 || e == a.length - 2) {
          final base = v(t[1]) > 5 ? 7.5 : 0.0;
          final h = math.max(1.0, v(t[1]) + sH * 0.85 - base);
          pylons.box(vm.Vector3(v(t[0]), base + h * 0.5, v(t[2])), vm.Vector3(0.32, h, 0.32), 0);
        }
      }
    }
    final m = fs.PhysicallyBasedMaterial(baseColorTexture: tex.wallRun, emissiveTexture: tex.wallRun)
      ..baseColorFactor = hexColor('#0F1C32', 1, 0.84)
      ..emissiveFactor = vm.Vector4(1.0, 0.92, 0.85, 1)
      ..roughnessFactor = 0.14
      ..metallicFactor = 0.35
      ..alphaMode = fs.AlphaMode.blend
      ..doubleSided = true;
    if (!panels.isEmpty) refRoot.add(fs.Node(name: 'WallRunPanelsMerged', mesh: fs.Mesh(panels.build(), m)));
    if (!pylons.isEmpty) {
      refRoot.add(fs.Node(
          name: 'WallRunSupportPylons',
          mesh: fs.Mesh(pylons.build(), pbr(hexColor('#1C2536'), roughness: 0.5, metallic: 0.72))));
    }
  }



  // ------------------------------------- DistantTokyoSkyline360 (demo)
  void _distantSkyline() {
    // Mulberry32-seeded ring of 96 towers at r = 420..565 around the origin.
    var seed = (14598366 + 77) & 0xFFFFFFFF;
    double rnd() {
      seed = (seed + 0x6D2B79F5) & 0xFFFFFFFF;
      var t = seed;
      t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF;
      t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0;
    }

    final walls = MeshBuf();
    for (int e = 0; e < 96; e++) {
      final t = e / 96 * math.pi * 2 + (rnd() - 0.5) * 0.035;
      final r = 420 + rnd() * 145;
      final a = 18 + rnd() * 28, o = 16 + rnd() * 24;
      final h = 42 + math.pow(rnd(), 1.25) * 185;
      final cx = math.cos(t) * r, cz = math.sin(t) * r;
      // box rotated by -t about Y (three.js rotateY(-t))
      final ca = math.cos(-t), sa = math.sin(-t);
      XZ c(double lx, double lz) => XZ(cx + lx * ca + lz * sa, cz - lx * sa + lz * ca);
      final fp = [c(-a / 2, -o / 2), c(a / 2, -o / 2), c(a / 2, o / 2), c(-a / 2, o / 2)];
      _prism(walls, MeshBuf(), fp, -0.5, h - 0.5);
    }
    _add(
        walls,
        pbr(hexColor('#243656'), roughness: 0.68, metallic: 0.24)
          ..baseColorTexture = tex.glassBase
          ..emissiveTexture = tex.glassGlow
          ..emissiveFactor = hexColor('#7FB3F2', 0.52 * 1.6),
        'DistantTokyoSkyline360');
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
