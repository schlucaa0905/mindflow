import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'spike/spike_screen.dart';

void main() {
  runApp(const MindFlowApp());
}

class MindFlowApp extends StatelessWidget {
  const MindFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindFlow',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: const SpikeScreen(),
    );
  }
}
