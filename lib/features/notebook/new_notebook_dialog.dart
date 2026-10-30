import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import 'notebook_cover.dart';
import 'page_painter.dart';

/// Farben für Notizbuch-Umschläge.
const kCoverColors = <int>[
  0xFF8B7CF6, 0xFF6366F1, 0xFF3B82F6, 0xFF0EA5E9,
  0xFF14B8A6, 0xFF22C55E, 0xFF84CC16, 0xFFF59E0B,
  0xFFF97316, 0xFFEF4444, 0xFFEC4899, 0xFF64748B,
  0xFF1F2937, 0xFF78350F,
];

/// Ergebnis des Dialogs.
class NotebookDraft {
  NotebookDraft({
    required this.title,
    required this.category,
    required this.cover,
    required this.coverStyle,
    required this.paper,
    required this.format,
    required this.template,
  });

  final String title;
  final String category;
  final int cover;
  final CoverStyle coverStyle;
  final Paper paper;
  final PageFormat format;
  final PageTemplate template;

  Map<String, dynamic> toData() => {
        'cover': cover,
        'coverStyle': coverStyle.name,
        'paper': paper.name,
        'format': format.name,
        'template': template.name,
        if (category.isNotEmpty) 'category': category,
      };
}

/// Dialog "Neues Notizbuch" mit Live-Vorschau.
/// Mit [initial] dient er auch zum Bearbeiten eines bestehenden Notizbuchs.
Future<NotebookDraft?> showNotebookDialog(
  BuildContext context, {
  required List<String> categories,
  required int suggestedCover,
  MfObject? initial,
}) {
  return showDialog<NotebookDraft>(
    context: context,
    builder: (_) => _NotebookDialog(
      categories: categories,
      suggestedCover: suggestedCover,
      initial: initial,
    ),
  );
}

class _NotebookDialog extends StatefulWidget {
  const _NotebookDialog({
    required this.categories,
    required this.suggestedCover,
    this.initial,
  });

  final List<String> categories;
  final int suggestedCover;
  final MfObject? initial;

  @override
  State<_NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<_NotebookDialog> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late int _cover;
  late CoverStyle _style;
  late Paper _paper;
  late PageFormat _format;
  late PageTemplate _template;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    _title = TextEditingController(text: o?.title ?? '');
    _category = TextEditingController(text: o?.category ?? '');
    _cover = o?.coverColor ?? widget.suggestedCover;
    _style = o?.coverStyle ?? CoverStyle.solid;
    _paper = o?.paper ?? Paper.dark;
    _format = o?.format ?? PageFormat.a4Portrait;
    _template = o?.template ?? PageTemplate.lined;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initial == null && _paper == Paper.dark) {
      _paper = Theme.of(context).brightness == Brightness.dark
          ? Paper.dark
          : Paper.light;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      NotebookDraft(
        title: _title.text.trim().isEmpty ? 'Neues Notizbuch' : _title.text.trim(),
        category: _category.text.trim(),
        cover: _cover,
        coverStyle: _style,
        paper: _paper,
        format: _format,
        template: _template,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: mf.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 860, maxHeight: size.height * 0.9),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          final preview = _Preview(
            cover: Color(_cover),
            style: _style,
            title: _title.text,
            category: _category.text.trim(),
            paper: PaperStyle.of(_paper),
            template: _template,
            format: _format,
            compact: !wide,
          );
          final options = _options(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
                child: Row(
                  children: [
                    Text(_editing ? 'Notizbuch bearbeiten' : 'Neues Notizbuch',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: mf.text)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 280,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 8, 8, 24),
                              child: preview,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 24, 24),
                              child: options,
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Column(
                          children: [preview, const SizedBox(height: 20), options],
                        ),
                      ),
              ),
              Divider(height: 1, color: mf.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Abbrechen')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(_editing ? 'Speichern' : 'Notizbuch erstellen'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _options(BuildContext context) {
    final mf = context.mf;
    final suggestions = widget.categories
        .where((c) => c.toLowerCase() != _category.text.trim().toLowerCase())
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section('Titel', mf),
        TextField(
          controller: _title,
          autofocus: !_editing,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: 'z. B. Netzwerktechnik'),
        ),
        const SizedBox(height: 18),
        _Section('Kategorie / Fach', mf),
        TextField(
          controller: _category,
          onChanged: (_) => setState(() {}),
          decoration:
              const InputDecoration(hintText: 'z. B. Informatik (optional)'),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in suggestions)
                ActionChip(
                  label: Text(c),
                  onPressed: () => setState(() => _category.text = c),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _Section('Umschlag', mf),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kCoverColors)
              GestureDetector(
                onTap: () => setState(() => _cover = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _cover == c ? mf.text : Colors.transparent,
                        width: 2.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in CoverStyle.values)
              ChoiceChip(
                label: Text(s.label),
                selected: _style == s,
                onSelected: (_) => setState(() => _style = s),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _Section('Papier', mf),
        SegmentedButton<Paper>(
          showSelectedIcon: false,
          segments: [
            for (final p in Paper.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {_paper},
          onSelectionChanged: (s) => setState(() => _paper = s.first),
        ),
        const SizedBox(height: 18),
        _Section('Format', mf),
        SegmentedButton<PageFormat>(
          showSelectedIcon: false,
          segments: [
            for (final f in PageFormat.values)
              ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {_format},
          onSelectionChanged: (s) => setState(() => _format = s.first),
        ),
        const SizedBox(height: 22),
        _Section('Vorlage für neue Seiten', mf),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in PageTemplate.values)
              _TemplateTile(
                template: t,
                paper: PaperStyle.of(_paper),
                format: _format,
                selected: _template == t,
                onTap: () => setState(() => _template = t),
              ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text, this.mf);
  final String text;
  final MfPalette mf;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: mf.textMuted)),
      );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.paper,
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final PageTemplate template;
  final PaperStyle paper;
  final PageFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 112,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: paper.desk,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? mf.accent : mf.border,
                    width: selected ? 2.5 : 1),
              ),
              child: CustomPaint(
                size: Size.infinite,
                painter: TemplatePreviewPainter(paper, template, format),
              ),
            ),
            const SizedBox(height: 6),
            Text(template.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? mf.text : mf.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Vorschau: Umschlag und erste Seite nebeneinander bzw. übereinander.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.cover,
    required this.style,
    required this.title,
    required this.category,
    required this.paper,
    required this.template,
    required this.format,
    required this.compact,
  });

  final Color cover;
  final CoverStyle style;
  final String title;
  final String category;
  final PaperStyle paper;
  final PageTemplate template;
  final PageFormat format;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final coverWidget = AspectRatio(
      aspectRatio: 0.74,
      child: DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [
          BoxShadow(
              color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 10)),
        ]),
        child: NotebookCover(
            color: cover, style: style, title: title, category: category),
      ),
    );
    final pageWidget = Container(
      decoration: BoxDecoration(
        color: paper.desk,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mf.border),
      ),
      padding: const EdgeInsets.all(10),
      child: CustomPaint(
        size: Size.infinite,
        painter: TemplatePreviewPainter(paper, template, format),
      ),
    );
    if (compact) {
      return SizedBox(
        height: 190,
        child: Row(
          children: [
            Expanded(child: Center(child: coverWidget)),
            const SizedBox(width: 16),
            Expanded(child: pageWidget),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        coverWidget,
        const SizedBox(height: 20),
        SizedBox(height: 200, child: pageWidget),
        const SizedBox(height: 8),
        Text('Erste Seite: ${template.label}, ${format.label}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: mf.textMuted)),
      ],
    );
  }
}
