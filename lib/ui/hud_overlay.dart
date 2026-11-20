import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/neon_palette.dart';

/// Faithful recreation of the in-game HUD shown in the Neon Scramble video:
/// - Subtle diagonal rain streaks overlay
/// - Top-left compact stats bar (NEON SCRAMBLE | SCORE | SPEED | COMBO | phase pill)
/// - Top-right Auto-Pilot, Mute, and Map/Pause controls
/// - Bottom-center combo/trick toast pill
/// - Bottom-right live Shibuya route minimap with Japanese + English zone header
/// - Finale ("SHIBUYA IGNITED" + Play Again + Photo Mode) and Crash overlays
class HudOverlay extends StatelessWidget {
  const HudOverlay({
    super.key,
    required this.state,
    required this.onToggleAutoPilot,
    required this.onToggleMute,
    required this.onTogglePause,
    required this.onTogglePhotoMode,
    required this.onPlayAgain,
    required this.onReturnToMap,
  });

  final GameState state;
  final VoidCallback onToggleAutoPilot;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePause;
  final VoidCallback onTogglePhotoMode;
  final VoidCallback onPlayAgain;
  final VoidCallback onReturnToMap;

  String _formatInt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Subtle Tokyo night rain streaks during gameplay
        if (state.screen == GameScreen.playing)
          IgnorePointer(
            child: CustomPaint(
              painter: _RainStreaksPainter(time: state.elapsedSeconds),
            ),
          ),

        // Top HUD bar (hidden in Photo Mode except exit button)
        if (!state.photoMode)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TopLeftStatsBar(
                    scoreText: _formatInt(state.score),
                    speedText: '${state.speedKmh.round()} km/h',
                    comboText: '${state.combo}x',
                    badge: state.actionBadge,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _PillButton(
                        label: 'Auto-Pilot',
                        active: state.autoPilotEnabled,
                        onTap: onToggleAutoPilot,
                      ),
                      _PillButton(
                        label: state.muted ? 'Muted' : 'Mute',
                        icon: state.muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        active: false,
                        onTap: onToggleMute,
                      ),
                      _IconPillButton(
                        icon: Icons.menu_rounded,
                        onTap: onTogglePause,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Photo Mode exit pill
        if (state.photoMode)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _PillButton(
                  label: 'Exit Photo Mode (Drag to Orbit)',
                  active: true,
                  onTap: onTogglePhotoMode,
                ),
              ),
            ),
          ),

        // Bottom-center trick / boost toast pill
        if (!state.photoMode &&
            state.screen == GameScreen.playing &&
            state.activeToast != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xDC080D1A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Color(state.activeToast!.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      state.activeToast!.label,
                      style: const TextStyle(
                        color: NeonPalette.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      state.activeToast!.bonusText,
                      style: TextStyle(
                        color: Color(state.activeToast!.colorValue),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bottom-right live Shibuya minimap
        if (!state.photoMode &&
            (state.screen == GameScreen.playing ||
                state.screen == GameScreen.victory))
          Positioned(
            right: 14,
            bottom: 14,
            child: _LiveMinimapCard(
              zoneLabel: state.currentZone.displayLabel,
              progress: state.routeProgress,
            ),
          ),

        // Finale bottom-center card ("SHIBUYA IGNITED" + Play Again + Photo Mode)
        if (!state.photoMode && state.screen == GameScreen.victory)
          Positioned(
            left: 16,
            right: 16,
            bottom: 22,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xE80A0F1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x40FFFFFF)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 24),
                  ],
                ),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SHIBUYA IGNITED',
                          style: TextStyle(
                            color: NeonPalette.accentOrange,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatInt(state.score)} PTS',
                          style: const TextStyle(
                            color: NeonPalette.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${state.maxSpeedKmh.round()} km/h  ·  MAX ${state.maxCombo}x',
                      style: const TextStyle(
                        color: NeonPalette.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: onPlayAgain,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NeonPalette.accentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Play Again',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onTogglePhotoMode,
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Photo Mode'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NeonPalette.textPrimary,
                        side: const BorderSide(color: Color(0x44FFFFFF)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Pause / Game Over modal cards
        if (state.screen == GameScreen.paused ||
            state.screen == GameScreen.gameOver)
          Container(
            color: const Color(0x88040710),
            child: Center(
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: NeonPalette.cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NeonPalette.cardBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.screen == GameScreen.paused
                          ? 'PAUSED'
                          : 'WIPEOUT IN SHIBUYA',
                      style: const TextStyle(
                        color: NeonPalette.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    if (state.crashReason != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        state.crashReason!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: NeonPalette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '${_formatInt(state.score)} PTS  ·  ${(state.routeProgress * 100).round()}% ROUTE',
                      style: const TextStyle(
                        color: NeonPalette.pegmanYellow,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (state.screen == GameScreen.paused)
                          ElevatedButton(
                            onPressed: onTogglePause,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NeonPalette.accentOrange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Resume'),
                          )
                        else
                          ElevatedButton(
                            onPressed: onPlayAgain,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NeonPalette.accentOrange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry Run'),
                          ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: onReturnToMap,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NeonPalette.textPrimary,
                            side: const BorderSide(color: Color(0x44FFFFFF)),
                          ),
                          child: const Text('Shibuya Map'),
                        ),
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

class _TopLeftStatsBar extends StatelessWidget {
  const _TopLeftStatsBar({
    required this.scoreText,
    required this.speedText,
    required this.comboText,
    required this.badge,
  });

  final String scoreText;
  final String speedText;
  final String comboText;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xD9080D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: NeonPalette.accentRedDot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'NEON SCRAMBLE',
                style: TextStyle(
                  color: NeonPalette.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          _StatCell(label: 'SCORE', value: scoreText),
          _StatCell(label: 'SPEED', value: speedText),
          _StatCell(label: 'COMBO', value: comboText),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x33FF5A1F),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x88FF5A1F)),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: NeonPalette.pegmanYellow,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: NeonPalette.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: NeonPalette.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x38FF5A1F) : const Color(0xD9080D1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? NeonPalette.accentOrange : const Color(0x30FFFFFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: NeonPalette.textPrimary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: active ? NeonPalette.pegmanYellow : NeonPalette.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xD9080D1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x30FFFFFF)),
        ),
        child: Icon(icon, size: 16, color: NeonPalette.textPrimary),
      ),
    );
  }
}

class _LiveMinimapCard extends StatelessWidget {
  const _LiveMinimapCard({
    required this.zoneLabel,
    required this.progress,
  });

  final String zoneLabel;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 196,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xDC080D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zoneLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NeonPalette.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _MinimapRoutePainter(progress: progress),
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimapRoutePainter extends CustomPainter {
  _MinimapRoutePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = const Color(0xFF060A14),
    );

    final pts = [
      Offset(size.width * 0.14, size.height * 0.25),
      Offset(size.width * 0.44, size.height * 0.22),
      Offset(size.width * 0.54, size.height * 0.56),
      Offset(size.width * 0.86, size.height * 0.78),
    ];

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // Highlight Yamanote middle segment in green
    canvas.drawLine(
      pts[1],
      pts[2],
      Paint()
        ..color = NeonPalette.yamanoteGreen
        ..strokeWidth = 2.8,
    );

    // Pegman live dot interpolated along the 3 route segments
    final segFloat = progress * 3.0;
    final segIndex = segFloat.floor().clamp(0, 2);
    final segT = (segFloat - segIndex).clamp(0.0, 1.0);
    final livePos = Offset.lerp(pts[segIndex], pts[segIndex + 1], segT)!;

    canvas.drawCircle(
      pts.last,
      4,
      Paint()..color = NeonPalette.googleRed,
    );
    canvas.drawCircle(
      livePos,
      6.5,
      Paint()..color = NeonPalette.accentOrange.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      livePos,
      3.5,
      Paint()..color = NeonPalette.pegmanYellow,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapRoutePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _RainStreaksPainter extends CustomPainter {
  _RainStreaksPainter({required this.time});

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x36DCE8FF)
      ..strokeWidth = 1.1;

    const count = 42;
    for (int i = 0; i < count; i++) {
      final seed = i * 73.13;
      final x = ((seed * 19.7) % size.width);
      final y =
          ((seed * 31.3 + time * (520 + (i % 5) * 75)) % (size.height + 60)) -
              30;
      final len = 14.0 + (i % 4) * 5.0;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - 3.5, y + len),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainStreaksPainter oldDelegate) =>
      oldDelegate.time != time;
}
