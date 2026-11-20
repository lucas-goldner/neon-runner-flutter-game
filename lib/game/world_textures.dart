import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart' as fs;

import 'level_data.dart';

/// Procedurally painted textures for the Shibuya night city (window facades,
/// the dark-mode Google-Maps style ground, and neon sign faces).
class WorldTextures {
  late final fs.Texture2D facadeBase;
  late final fs.Texture2D facadeGlow;
  late final fs.Texture2D glassBase;
  late final fs.Texture2D glassGlow;
  late final fs.Texture2D brickBase;
  late final fs.Texture2D brickGlow;
  late final fs.Texture2D shopBase;
  late final fs.Texture2D shopGlow;
  late final fs.Texture2D ground;
  final List<fs.Texture2D> googleGlyphs = [];

  static Future<WorldTextures> create(ShibuyaLevel level) async {
    final t = WorldTextures();
    final f = await _facade(seed: 7, glass: false);
    t.facadeBase = await fs.Texture2D.fromImage(f.$1);
    t.facadeGlow = await fs.Texture2D.fromImage(f.$2);
    final g = await _facade(seed: 19, glass: true);
    t.glassBase = await fs.Texture2D.fromImage(g.$1);
    t.glassGlow = await fs.Texture2D.fromImage(g.$2);
    final br = await _facade(seed: 31, glass: false, brick: true);
    t.brickBase = await fs.Texture2D.fromImage(br.$1);
    t.brickGlow = await fs.Texture2D.fromImage(br.$2);
    final sh = await _storefront();
    t.shopBase = await fs.Texture2D.fromImage(sh.$1);
    t.shopGlow = await fs.Texture2D.fromImage(sh.$2);
    t.ground = await fs.Texture2D.fromImage(await _ground(level));
    for (final ch in ['G', 'o', 'o', 'g', 'l', 'e']) {
      t.googleGlyphs.add(await fs.Texture2D.fromImage(await _glyph(ch)));
    }
    return t;
  }

  /// A tile of 8 x 16 windows. Returns (base colour, emissive) images.
  static Future<(ui.Image, ui.Image)> _facade(
      {required int seed, required bool glass, bool brick = false}) async {
    const w = 256, h = 512, cols = 8, rows = 16;
    final rng = math.Random(seed);
    final rb = ui.PictureRecorder();
    final re = ui.PictureRecorder();
    final cb = Canvas(rb);
    final ce = Canvas(re);
    final wall = brick
        ? const Color(0xFF3A2A2E)
        : (glass ? const Color(0xFF1B2D57) : const Color(0xFF17264A));
    cb.drawRect(const Rect.fromLTWH(0, 0, 256, 512), Paint()..color = wall);
    // faint facade self-illumination so towers read as deep sapphire blue
    ce.drawRect(const Rect.fromLTWH(0, 0, 256, 512),
        Paint()
          ..color = brick
              ? const Color(0xFF140F16)
              : (glass ? const Color(0xFF0E1A3A) : const Color(0xFF0B1531)));
    if (brick) {
      // brick coursing
      final mortar = Paint()..color = const Color(0xFF2C2024);
      for (double y = 0; y < 512; y += 8) {
        cb.drawRect(Rect.fromLTWH(0, y, 256, 1.5), mortar);
      }
    }
    final cw = w / cols, chh = h / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(c * cw + cw * 0.18, r * chh + chh * 0.22,
            cw * 0.64, chh * 0.5);
        final roll = rng.nextDouble();
        Color base;
        Color glow;
        if (roll < 0.22) {
          base = const Color(0xFFFFD08A);
          glow = Color.lerp(const Color(0xFFFFB45A), const Color(0xFFFFE2A8),
              rng.nextDouble())!;
        } else if (roll < 0.38) {
          base = const Color(0xFFA9D2FF);
          glow = Color.lerp(const Color(0xFF6FA8FF), const Color(0xFFCFE6FF),
              rng.nextDouble())!;
        } else {
          base = const Color(0xFF0E1830);
          glow = const Color(0xFF060C1C);
        }
        cb.drawRect(rect, Paint()..color = base);
        ce.drawRect(rect, Paint()..color = glow);
      }
    }
    // horizontal floor slab lines
    final slab = Paint()
      ..color = brick ? const Color(0xFF4A3638) : const Color(0xFF223766);
    for (int r = 0; r <= rows; r++) {
      cb.drawRect(Rect.fromLTWH(0, r * chh - 1.5, 256, 3), slab);
    }
    final a = await rb.endRecording().toImage(w, h);
    final b = await re.endRecording().toImage(w, h);
    return (a, b);
  }

  /// White glyph on black for the emissive Google sign letters.
  static Future<ui.Image> _glyph(String ch) async {
    const w = 128, h = 160;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 128, 160), Paint()..color = const Color(0xFF000000));
    final tp = TextPainter(
      text: TextSpan(
        text: ch,
        style: const TextStyle(
            fontFamily: 'Inter', fontSize: 132, fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF), height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2 - 8));
    return rec.endRecording().toImage(w, h);
  }

  /// Ground-floor shopfront band: big warm-lit panes between dark mullions.
  static Future<(ui.Image, ui.Image)> _storefront() async {
    const w = 256, h = 128;
    final rb = ui.PictureRecorder();
    final re = ui.PictureRecorder();
    final cb = Canvas(rb);
    final ce = Canvas(re);
    cb.drawRect(const Rect.fromLTWH(0, 0, 256, 128), Paint()..color = const Color(0xFF1A1418));
    ce.drawRect(const Rect.fromLTWH(0, 0, 256, 128), Paint()..color = const Color(0xFF000000));
    final rng = math.Random(5);
    for (int i = 0; i < 4; i++) {
      final x = i * 64.0;
      final lit = rng.nextDouble() < 0.8;
      final pane = Rect.fromLTWH(x + 5, 22, 54, 100);
      final warm = Color.lerp(const Color(0xFFFFB866), const Color(0xFFFFE0B0), rng.nextDouble())!;
      cb.drawRect(pane, Paint()..color = lit ? warm : const Color(0xFF2A2230));
      ce.drawRect(pane, Paint()..color = lit ? warm : const Color(0xFF0A0810));
      // mullions
      final mull = Paint()..color = const Color(0xFF15111A);
      cb.drawRect(Rect.fromLTWH(x + 31, 22, 3, 100), mull);
      ce.drawRect(Rect.fromLTWH(x + 31, 22, 3, 100), Paint()..color = const Color(0xFF000000));
      // fascia / awning strip
      cb.drawRect(Rect.fromLTWH(x, 6, 64, 12), Paint()..color = const Color(0xFF2B2230));
    }
    final a = await rb.endRecording().toImage(w, h);
    final b = await re.endRecording().toImage(w, h);
    return (a, b);
  }

  /// World-space ground texture over the overview bounds, adapted from the
  /// demo's `DarkModeGoogleMapsGround` canvas (roads, crosswalks, rails,
  /// parks, station platforms, river). 1 texel ≈ 0.46 m.
  static Future<ui.Image> _ground(ShibuyaLevel level) async {
    final ov = level.overview;
    final b = ov['bounds'] as Map<String, dynamic>;
    final minX = (b['minX'] as num).toDouble();
    final maxX = (b['maxX'] as num).toDouble();
    final minZ = (b['minZ'] as num).toDouble();
    final maxZ = (b['maxZ'] as num).toDouble();
    const c = 2048.0;
    final sx = c / (maxX - minX), sz = c / (maxZ - minZ);
    Offset p(XZ q) => Offset((q.x - minX) * sx, (q.z - minZ) * sz);
    // The demo paints at 4096 px; convert its pixel widths.
    double w(double px4096) => px4096 * 0.5;

    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    cv.drawRect(const Rect.fromLTWH(0, 0, c, c),
        Paint()..color = const Color(0xFF171E29));

    void strokeLines(List<List<XZ>> lines, Color col, double width) {
      final paint = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (final l in lines) {
        if (l.length < 2) continue;
        path.moveTo(p(l[0]).dx, p(l[0]).dy);
        for (int i = 1; i < l.length; i++) {
          path.lineTo(p(l[i]).dx, p(l[i]).dy);
        }
      }
      cv.drawPath(path, paint);
    }

    void fillPoly(List<XZ> pts, Color fill, Color stroke, double sw) {
      if (pts.length < 3) return;
      final path = Path()..moveTo(p(pts[0]).dx, p(pts[0]).dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(p(pts[i]).dx, p(pts[i]).dy);
      }
      path.close();
      cv.drawPath(path, Paint()..color = fill);
      cv.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw);
    }

    for (final park in ov['parks'] as List<dynamic>) {
      fillPoly(ShibuyaLevel.pts(park['points']), const Color(0xFF1B3B2B),
          const Color(0xFF2A5E44), w(4));
    }
    final river = ov['river'];
    if (river != null) {
      final rl = [ShibuyaLevel.pts(river['points'])];
      strokeLines(rl, const Color(0xFF1A3A63), w(52));
      strokeLines(rl, const Color(0xFF26538A), w(28));
    }
    for (final st in ov['stations'] as List<dynamic>) {
      fillPoly(ShibuyaLevel.pts(st['points']), const Color(0xFF222D3D),
          const Color(0xFF364963), w(3));
    }
    final roads = ov['roads'] as Map<String, dynamic>;
    List<List<XZ>> rl(String k) => ShibuyaLevel.lines(roads[k]);
    strokeLines(rl('pedestrian'), const Color(0xFF202A3A), w(7));
    strokeLines(rl('local'), const Color(0xFF1D2634), w(18));
    strokeLines(rl('local'), const Color(0xFF283447), w(12));
    strokeLines(rl('secondary'), const Color(0xFF263348), w(30));
    strokeLines(rl('secondary'), const Color(0xFF384862), w(21));
    strokeLines(rl('arterial'), const Color(0xFF2B364A), w(42));
    strokeLines(rl('arterial'), const Color(0xFF445572), w(31));

    final streets = level.streets;
    final poly = streets['scramblePolygon'];
    if (poly is List && poly.length >= 3) {
      final pts = ShibuyaLevel.pts(poly);
      final path = Path()..moveTo(p(pts[0]).dx, p(pts[0]).dy);
      for (final q in pts.skip(1)) {
        path.lineTo(p(q).dx, p(q).dy);
      }
      cv.drawPath(path..close(), Paint()..color = const Color(0xFF3E4E68));
    }
    // Zebra crosswalk stripes
    final cws = (ov['crosswalks'] ?? streets['crosswalks']) as List<dynamic>;
    for (final cw in cws) {
      final s = cw['start'] as List<dynamic>, e = cw['end'] as List<dynamic>;
      final a = p(XZ((s[0] as num).toDouble(), (s[1] as num).toDouble()));
      final bb = p(XZ((e[0] as num).toDouble(), (e[1] as num).toDouble()));
      final d = bb - a;
      final len = d.distance;
      if (len < 3) continue;
      final dir = d / len;
      final nrm = Offset(-dir.dy, dir.dx);
      final half = ((cw['width'] as num?)?.toDouble() ?? 9) * sx * 0.48;
      final count = ((cw['stripeCount'] as num?)?.toInt() ?? 12).clamp(8, 18);
      final paint = Paint()
        ..color = const Color(0xD9E2ECF8)
        ..strokeWidth = math.max(1.5, len / count * 0.45);
      for (int i = 0; i < count; i++) {
        final m = a + d * ((i + 0.5) / count);
        cv.drawLine(m - nrm * half, m + nrm * half, paint);
      }
    }
    strokeLines(rl('expressway'), const Color(0xFF4A3B1E), w(52));
    strokeLines(rl('expressway'), const Color(0xFF8E6E2B), w(34));

    final pic = rec.endRecording();
    return pic.toImage(c.toInt(), c.toInt());
  }
}
