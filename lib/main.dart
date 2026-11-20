import 'package:flutter/material.dart';

import 'game/neon_palette.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeonScrambleApp());
}

class NeonScrambleApp extends StatelessWidget {
  const NeonScrambleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEON SCRAMBLE — Shibuya Crossing → Google Tokyo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: NeonPalette.bgDark,
        colorScheme: const ColorScheme.dark(
          primary: NeonPalette.accentOrange,
          secondary: NeonPalette.neonCyan,
          surface: NeonPalette.cardBg,
        ),
      ),
      home: const NeonScrambleGameScreen(),
    );
  }
}
