import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../data/object_repository.dart';
import '../../ui/color_picker.dart';
import 'page_painter.dart';

/// Eigene Vorlage: als Bild gespeicherte Seite (Name, Bilddatei).
typedef CustomTemplate = ({String name, String file});

List<CustomTemplate> loadCustomTemplates(ObjectRepository repo) {
  try {
    return [
      for (final j in jsonDecode(repo.setting('customTemplates') ?? '[]')
          as List)
        (name: j['name'] as String, file: j['file'] as String)
    ];
  } catch (_) {
    return [];
  }
}

void saveCustomTemplates(ObjectRepository repo, List<CustomTemplate> list) =>
    repo.setSetting('customTemplates',
        jsonEncode([for (final t in list) {'name': t.name, 'file': t.file}]));

/// Ergebnis von „Seite gestalten“.
class PageDesign {
  const PageDesign({
    required this.template,
    required this.gap,
    required this.color,
    required this.allPages,
    required this.forNewPages,
    this.bgImage,
  });

  /// Eigene Vorlage (Bild) statt Linien – null = [template].
  final String? bgImage;
  final PageTemplate template;
  final double gap;

  /// Eigene Blattfarbe (ARGB) oder null = wie das Notizbuch.
  final int? color;
  final bool allPages;
  final bool forNewPages;
}

/// Fertige Blattfarben – von Papier bis Plakat. Dazu jede eigene Farbe.
const kPaperColors = <int>[
  0xFFFFFFFF, 0xFFF8F3E6, 0xFFECECEC, 0xFF2A2A30, 0xFF17171F, 0xFF000000,
  0xFFFFF59D, 0xFFFFD54F, 0xFFFFB74D, 0xFFFF7043, 0xFFF8BBD0, 0xFFEC407A,
  0xFFE53935, 0xFFB3E5FC, 0xFF42A5F5, 0xFF1565C0, 0xFFC8E6C9, 0xFF66BB6A,
  0xFF2E7D32, 0xFFD1C4E9, 0xFF7E57C2, 0xFF6D4C41,
];

/// Vorlage, Linienabstand und Blattfarbe einer Seite wählen – mit Vorschau.
Future<PageDesign?> showPageDesign(
  BuildContext context, {
  required MfObject page,
  required PaperStyle notebookPaper,
  required PageFormat format,
  required ObjectRepository repo,
}) {
  var template = page.template;
  final current = page.data['bgImage'] as String?;
  var bg = current;
  final g = page.data['gap'];
  var gap = [for (final e in kPageGaps) e.$1].reduce((a, b) =>
      ((g is num ? g.toDouble() : 1.0) - a).abs() <=
              ((g is num ? g.toDouble() : 1.0) - b).abs()
          ? a
          : b);
  final c = page.data['paperColor'];
  int? color = c is int ? c : null;
  var all = false, forNew = false;
  return showDialog<PageDesign>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final mf = ctx.mf;
      final style = notebookPaper.copyWith(
        sheet: color == null ? null : Color(color!),
        line: color == null
            ? null
            : isDarkSheet(Color(color!))
                ? const Color(0x38FFFFFF)
                : const Color(0x30000000),
        gap: gap,
      );
      Widget title(String t) => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(t,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: mf.textMuted)),
          );
      Widget swatch(int? v, {Widget? child, VoidCallback? onTap}) {
        final on = v == color && child == null;
        final fill = v == null ? notebookPaper.sheet : Color(v);
        final dot = GestureDetector(
            onTap: onTap ?? () => setState(() => color = v),
            child: Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: child == null ? fill : null,
                gradient: child == null
                    ? null
                    : const SweepGradient(colors: [
                        Colors.red, Colors.yellow, Colors.green,
                        Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                      ]),
                shape: BoxShape.circle,
                border: Border.all(
                    color: on ? mf.accent : mf.border, width: on ? 3 : 1),
              ),
              child: child ??
                  (v == null
                      ? Icon(Icons.auto_awesome_outlined,
                          size: 16, color: mf.textMuted)
                      : null),
            ),
          );
        return v == null || child != null
            ? Tooltip(
                message: v == null ? 'Wie das Notizbuch' : 'Eigene Farbe',
                child: dot)
            : dot;
      }

      return AlertDialog(
        title: const Text('Seite gestalten'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SizedBox(
                    height: 190,
                    width: 190 * format.width / format.height,
                    child: CustomPaint(
                        painter: TemplatePreviewPainter(
                            style, template, format,
                            image: bg)),
                  ),
                ),
                title('Vorlage'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in PageTemplate.values)
                    GestureDetector(
                      onTap: () => setState(() {
                        template = t;
                        bg = null;
                      }),
                      child: Column(children: [
                        Container(
                          width: 70,
                          height: 86,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: style.desk,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: t == template && bg == null
                                    ? mf.accent
                                    : mf.border,
                                width: t == template && bg == null ? 2.5 : 1),
                          ),
                          child: CustomPaint(
                              painter: TemplatePreviewPainter(style, t, format)),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 74,
                          child: Text(t.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: t == template
                                      ? mf.text
                                      : mf.textMuted)),
                        ),
                      ]),
                    ),
                  // Eigene Vorlagen (und ein vorhandenes Bild/PDF als Vorlage).
                  for (final ct in [
                    ...loadCustomTemplates(repo),
                    if (current != null &&
                        !loadCustomTemplates(repo)
                            .any((x) => x.file == current))
                      (name: 'Aktuelles Bild', file: current),
                  ])
                    GestureDetector(
                      onTap: () => setState(() => bg = ct.file),
                      onLongPress: () {
                        saveCustomTemplates(repo, [
                          for (final x in loadCustomTemplates(repo))
                            if (x.file != ct.file) x
                        ]);
                        setState(() {});
                      },
                      child: Column(children: [
                        Container(
                          width: 70,
                          height: 86,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: style.desk,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                                color: bg == ct.file ? mf.accent : mf.border,
                                width: bg == ct.file ? 2.5 : 1),
                          ),
                          child: CustomPaint(
                              painter: TemplatePreviewPainter(
                                  style, template, format,
                                  image: ct.file)),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 74,
                          child: Text(ct.name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: bg == ct.file
                                      ? mf.text
                                      : mf.textMuted)),
                        ),
                      ]),
                    ),
                ]),
                if (loadCustomTemplates(repo).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'Eigene Vorlage lange drücken: aus der Liste entfernen.',
                        style: TextStyle(fontSize: 11, color: mf.textMuted)),
                  ),
                title('Abstand der Linien und Kästchen'),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  segments: [
                    for (final e in kPageGaps)
                      ButtonSegment(value: e.$1, label: Text(e.$2)),
                  ],
                  selected: {gap},
                  onSelectionChanged: (s) => setState(() => gap = s.first),
                ),
                title('Blattfarbe'),
                Wrap(children: [
                  swatch(null),
                  for (final v in kPaperColors) swatch(v),
                  if (color != null && !kPaperColors.contains(color))
                    swatch(color),
                  swatch(
                    -1,
                    child: const Icon(Icons.add, size: 18, color: Colors.white),
                    onTap: () async {
                      final picked = await pickColor(ctx,
                          color == null ? notebookPaper.sheet : Color(color!));
                      if (picked != null) {
                        setState(() => color = picked.withAlpha(255).toARGB32());
                      }
                    },
                  ),
                ]),
                title('Anwenden auf'),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Diese Seite')),
                    ButtonSegment(value: true, label: Text('Alle Seiten')),
                  ],
                  selected: {all},
                  onSelectionChanged: (s) => setState(() => all = s.first),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: forNew,
                  onChanged: (v) => setState(() => forNew = v ?? false),
                  title: const Text('Auch für neue Seiten verwenden'),
                ),
                Text(
                    'Handschrift und Textfelder bleiben, nur das Papier '
                    'dahinter ändert sich.',
                    style: TextStyle(fontSize: 12, color: mf.textMuted)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx,
                PageDesign(
                    template: template,
                    gap: gap,
                    color: color,
                    allPages: all,
                    forNewPages: forNew,
                    bgImage: bg)),
            child: const Text('Übernehmen'),
          ),
        ],
      );
    }),
  );
}
