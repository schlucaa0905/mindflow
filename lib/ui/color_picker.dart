import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Farbwähler: Vorschläge plus freie Wahl über Farbton, Sättigung, Helligkeit.
Future<Color?> pickColor(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(initial: initial),
  );
}

const _swatches = <int>[
  0xFF1C1C22, 0xFF6B7280, 0xFFEDEDF2, 0xFFFFFFFF,
  0xFFDC2626, 0xFFF97316, 0xFFF59E0B, 0xFFEAB308,
  0xFF16A34A, 0xFF10B981, 0xFF0EA5E9, 0xFF2563EB,
  0xFF6D5DE7, 0xFF8B7CF6, 0xFFC026D3, 0xFFDB2777,
  0xFF7C2D12, 0xFF365314, 0xFF1E3A8A, 0xFF4C1D95,
];

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return AlertDialog(
      title: const Text('Farbe wählen'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _swatches)
                  GestureDetector(
                    onTap: () => setState(() => _hsv = HSVColor.fromColor(Color(c))),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.toARGB32() == c ? mf.accent : mf.border,
                          width: _color.toARGB32() == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _GradientSlider(
              label: 'Farbton',
              value: _hsv.hue / 360,
              colors: [
                for (var h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()
              ],
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v * 360)),
            ),
            _GradientSlider(
              label: 'Sättigung',
              value: _hsv.saturation,
              colors: [
                _hsv.withSaturation(0).toColor(),
                _hsv.withSaturation(1).toColor(),
              ],
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Helligkeit',
              value: _hsv.value,
              colors: [Colors.black, _hsv.withValue(1).toColor()],
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
            const SizedBox(height: 12),
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: mf.border),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _color),
            child: const Text('Übernehmen')),
      ],
    );
  }
}

/// Schieberegler mit Farbverlauf als Hintergrund.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: mf.textMuted)),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            void update(Offset local) =>
                onChanged((local.dx / w).clamp(0.0, 1.0).toDouble());
            return GestureDetector(
              onTapDown: (d) => update(d.localPosition),
              onHorizontalDragUpdate: (d) => update(d.localPosition),
              child: SizedBox(
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      top: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: mf.border),
                        ),
                      ),
                    ),
                    Positioned(
                      left: value.clamp(0.0, 1.0) * w - 10,
                      top: 2,
                      child: Container(
                        width: 20,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(color: Color(0x55000000), blurRadius: 4)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
