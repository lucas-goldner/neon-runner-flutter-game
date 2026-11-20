import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hud_icons.dart';
import 'ui_tokens.dart';

/// `.maps-title-card` (lower-third start card) + `.osm-attribution-badge`.
class MapsTitleCard extends StatelessWidget {
  const MapsTitleCard({super.key, required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width <= 1180;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 34,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.min(488, size.width - 40),
                maxWidth: size.width - 40,
              ),
              child: IntrinsicWidth(
                child: GlassDock(
                  radius: 22,
                  color: Ui.surfaceGlassStrong,
                  padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const PlasmaDot(),
                                  const SizedBox(width: 10),
                                  Text(
                                    'NEON SCRAMBLE',
                                    style: Ui.ui(
                                      28,
                                      weight: FontWeight.w700,
                                      letterSpacingEm: 0.05,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Padding(
                                padding: const EdgeInsets.only(left: 18),
                                child: Text(
                                  'Shibuya Crossing → Google Tokyo',
                                  style: Ui.ui(
                                    14,
                                    weight: FontWeight.w500,
                                    color: Ui.textStrongSub,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 28),
                          _PlayButton(onTap: onPlay),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.only(top: 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Ui.borderSubtle),
                          ),
                        ),
                        child: const ControlsStrip(
                          items: [
                            (['A', 'D'], 'Lanes', true),
                            (['Space'], 'Jump / Roof Vault', false),
                            (['S'], 'Slide', false),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          bottom: compact ? null : 20,
          top: compact ? 16 : null,
          child: const OsmAttributionBadge(),
        ),
      ],
    );
  }
}

/// Row of `<kbd>` groups separated by `·` (title strip and onboarding hint).
class ControlsStrip extends StatelessWidget {
  const ControlsStrip({
    super.key,
    required this.items,
    this.slashed = true,
    this.color = Ui.textSecondary,
  });

  final Color color;

  /// (keys, label, use "/" between keys)
  final List<(List<String>, String, bool)> items;
  final bool slashed;

  @override
  Widget build(BuildContext context) {
    final style = Ui.ui(12.5, weight: FontWeight.w500, color: color);
    final sepStyle =
        Ui.ui(12.5, weight: FontWeight.w500, color: Ui.textSecondary);
    final children = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final (keys, label, slash) = items[i];
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Opacity(opacity: 0.65, child: Text('·', style: sepStyle)),
        ));
      }
      final group = <Widget>[];
      for (int k = 0; k < keys.length; k++) {
        if (k > 0) {
          group.add(const SizedBox(width: 5));
          if (slash && slashed) {
            group.add(Opacity(
              opacity: 0.72,
              child: Text('/',
                  style: Ui.ui(11,
                      weight: FontWeight.w500, color: Ui.textSecondary)),
            ));
            group.add(const SizedBox(width: 5));
          }
        }
        group.add(Kbd(keys[k]));
      }
      group.add(const SizedBox(width: 5));
      group.add(Text(label, style: style));
      children.add(Row(mainAxisSize: MainAxisSize.min, children: group));
    }
    return DefaultTextStyle(
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}

class OsmAttributionBadge extends StatelessWidget {
  const OsmAttributionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: GlassDock(
        color: const Color(0xD10B0F19),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'Map data © OpenStreetMap contributors',
          style: Ui.ui(11,
              weight: FontWeight.w500, color: Ui.textStrongSub, height: 1.2),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverPress(
      onTap: onTap,
      lift: 1.5,
      builder: (context, hover) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          gradient: Ui.primaryGradient,
          borderRadius: BorderRadius.circular(9999),
          boxShadow: [
            BoxShadow(
              color: hover ? const Color(0x7AFF6B1A) : const Color(0x5CFF6B1A),
              blurRadius: hover ? 28 : 24,
              offset: Offset(0, hover ? 12 : 8),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          border: Border(
            top: BorderSide(
              color: hover ? const Color(0x6BFFFFFF) : const Color(0x52FFFFFF),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PlayTriangleIcon(size: 15, color: Ui.bgAbyssal),
            const SizedBox(width: 8),
            Text(
              'PLAY',
              style: Ui.ui(16,
                  weight: FontWeight.w700,
                  color: Ui.bgAbyssal,
                  letterSpacingEm: 0.08,
                  height: 1),
            ),
          ],
        ),
      ),
    );
  }
}
