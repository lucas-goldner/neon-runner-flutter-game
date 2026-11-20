import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/neon_palette.dart';

/// Stylized dark Shibuya map overview matching the 0:00–0:01 start screen:
/// glowing cyan, green (Yamanote), purple, and orange transit corridors,
/// concentric target markers for Shibuya Scramble Crossing & Shibuya Stream -
/// Google Tokyo, and the bottom-center Play card with keyboard hints.
class MapOverviewScreen extends StatefulWidget {
  const MapOverviewScreen({
    super.key,
    required this.onPlay,
  });

  final VoidCallback onPlay;

  @override
  State<MapOverviewScreen> createState() => _MapOverviewScreenState();
}

class _MapOverviewScreenState extends State<MapOverviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return CustomPaint(
              painter: _ShibuyaMapPainter(phase: _pulse.value),
            );
          },
        ),
        // Bottom-left attribution
        const Positioned(
          left: 14,
          bottom: 10,
          child: Text(
            'Stylized Shibuya map · Inspired by OpenStreetMap contributors',
            style: TextStyle(
              color: Color(0x8894A3B8),
              fontSize: 10,
            ),
          ),
        ),
        // Bottom-center Play card
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28, left: 16, right: 16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xEB0A0F1E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: NeonPalette.cardBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: NeonPalette.accentRedDot,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: NeonPalette.accentOrange,
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'NEON SCRAMBLE',
                                style: TextStyle(
                                  color: NeonPalette.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Shibuya Crossing → Google Tokyo',
                            style: TextStyle(
                              color: NeonPalette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.onPlay,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text(
                          'PLAY',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NeonPalette.accentOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 8,
                          shadowColor: const Color(0x99FF5A1F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0x1FFFFFFF)),
                  const SizedBox(height: 10),
                  const Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _ControlHint(keys: ['A', 'D'], label: 'Lanes'),
                      _ControlHint(keys: ['Space'], label: 'Jump / Roof Vault'),
                      _ControlHint(keys: ['S'], label: 'Slide'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlHint extends StatelessWidget {
  const _ControlHint({required this.keys, required this.label});

  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0x38FFFFFF)),
            ),
            child: Text(
              k,
              style: const TextStyle(
                color: NeonPalette.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: const TextStyle(
            color: NeonPalette.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _ShibuyaMapPainter extends CustomPainter {
  _ShibuyaMapPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Deep slate-navy base
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A101E),
    );

    // Subtle city block street grid
    final gridPaint = Paint()
      ..color = const Color(0x16FFFFFF)
      ..strokeWidth = 1.0;
    for (double x = 0; x < w; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x + 28, h), gridPaint);
    }
    for (double y = 0; y < h; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(w, y - 22), gridPaint);
    }

    // Glowing transit & arterial corridors matching the video's Shibuya map
    _drawGlowPath(
      canvas,
      Path()
        ..moveTo(w * 0.54, 0)
        ..cubicTo(w * 0.53, h * 0.35, w * 0.57, h * 0.65, w * 0.72, h),
      NeonPalette.yamanoteGreen,
      4.0,
    );
    _drawGlowPath(
      canvas,
      Path()
        ..moveTo(0, h * 0.78)
        ..quadraticBezierTo(w * 0.35, h * 0.42, w, h * 0.16),
      NeonPalette.neonPurple,
      3.5,
    );
    _drawGlowPath(
      canvas,
      Path()
        ..moveTo(w * 0.10, h)
        ..cubicTo(w * 0.40, h * 0.72, w * 0.68, h * 0.58, w, h * 0.54),
      const Color(0xFFEAB308),
      5.0,
    );
    _drawGlowPath(
      canvas,
      Path()
        ..moveTo(w * 0.62, 0)
        ..quadraticBezierTo(w * 0.64, h * 0.45, w * 0.76, h),
      NeonPalette.neonCyan,
      3.2,
    );

    // Active runner route ribbon: Scramble Crossing -> Station -> Shibuya Stream
    final scramblePos = Offset(w * 0.40, h * 0.28);
    final stationPos = Offset(w * 0.54, h * 0.44);
    final googlePos = Offset(w * 0.71, h * 0.74);

    final routePath = Path()
      ..moveTo(scramblePos.dx, scramblePos.dy)
      ..quadraticBezierTo(w * 0.52, h * 0.26, stationPos.dx, stationPos.dy)
      ..quadraticBezierTo(w * 0.64, h * 0.56, googlePos.dx, googlePos.dy);
    _drawGlowPath(canvas, routePath, NeonPalette.accentOrange, 4.2);

    // Concentric pulsing target rings
    _drawTargetRings(canvas, scramblePos, NeonPalette.accentOrange, NeonPalette.neonCyan);
    _drawTargetRings(canvas, googlePos, NeonPalette.googleRed, NeonPalette.googleBlue);

    // Station dot
    canvas.drawCircle(stationPos, 5.5, Paint()..color = NeonPalette.yamanoteGreen);
    canvas.drawCircle(
      stationPos,
      8.5,
      Paint()
        ..color = NeonPalette.yamanoteGreen.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Map labels
    _drawMapTag(canvas, scramblePos + const Offset(14, 10), 'Shibuya Scramble Crossing', NeonPalette.accentRedDot);
    _drawMapTag(canvas, stationPos + const Offset(12, -10), 'Shibuya Station', NeonPalette.yamanoteGreen);
    _drawMapTag(canvas, googlePos + const Offset(14, 12), 'Shibuya Stream - Google Tokyo', NeonPalette.googleRed);
  }

  void _drawGlowPath(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3.4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawTargetRings(Canvas canvas, Offset center, Color inner, Color outer) {
    final pulseR = 18.0 + math.sin(phase * math.pi * 2) * 8.0;
    for (final r in [pulseR, pulseR + 14.0, pulseR + 28.0]) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = outer.withValues(alpha: (0.45 - (r - 18) * 0.008).clamp(0.08, 0.5))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
    canvas.drawCircle(center, 7, Paint()..color = inner);
  }

  void _drawMapTag(Canvas canvas, Offset offset, String text, Color dotColor) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: NeonPalette.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx, offset.dy, tp.width + 22, tp.height + 10),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xD6090E1B));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(offset.dx + 9, offset.dy + (tp.height + 10) / 2),
      3.5,
      Paint()..color = dotColor,
    );
    tp.paint(canvas, Offset(offset.dx + 17, offset.dy + 5));
  }

  @override
  bool shouldRepaint(covariant _ShibuyaMapPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
