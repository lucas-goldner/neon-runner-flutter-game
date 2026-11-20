import 'package:flutter/material.dart';

import '../game/neon_palette.dart';

/// Matches the neon-scramble.ai.studio dark navy loading screen with subtle
/// warm orange radial glow and centered "NEON SCRAMBLE" progress card.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    required this.progress,
    required this.label,
  });

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 100);

    return Container(
      decoration: const BoxDecoration(
        color: NeonPalette.bgDark,
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            Color(0x38FF5A1F),
            Color(0x14FF5A1F),
            NeonPalette.bgDark,
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
          decoration: BoxDecoration(
            color: NeonPalette.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NeonPalette.cardBorder, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: NeonPalette.accentRedDot,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: NeonPalette.accentOrange,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'NEON SCRAMBLE',
                    style: TextStyle(
                      color: NeonPalette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Shibuya Crossing → Google Tokyo',
                style: TextStyle(
                  color: NeonPalette.textMuted,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0x22FFFFFF),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    NeonPalette.accentOrange,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: NeonPalette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      color: NeonPalette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
