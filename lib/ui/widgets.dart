import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Schwebendes Panel (Werkzeugleisten, Seiten-Navigation).
class FloatingPanel extends StatelessWidget {
  const FloatingPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: mf.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mf.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final enabled = onTap != null;
    final color = !enabled
        ? mf.textMuted.withValues(alpha: 0.35)
        : danger
            ? mf.danger
            : selected
                ? mf.accent
                : mf.text;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? mf.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  const ColorDot(
      {super.key,
      required this.color,
      required this.selected,
      required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 40,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: selected ? 22 : 18,
          height: selected ? 22 : 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? mf.accent : mf.border,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class WidthDot extends StatelessWidget {
  const WidthDot(
      {super.key,
      required this.width,
      required this.selected,
      required this.onTap});

  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? mf.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Container(
          width: width * 2.4,
          height: width * 2.4,
          decoration: BoxDecoration(
            color: selected ? mf.accent : mf.text,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class PanelDivider extends StatelessWidget {
  const PanelDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: context.mf.border,
    );
  }
}

/// Überschrift eines Bereichs mit optionaler Aktion rechts.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.mf.text)),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Seitentitel oben in einem Bereich.
class PageHeader extends StatelessWidget {
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: mf.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!,
                        style: TextStyle(color: mf.textMuted, fontSize: 14)),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Leerer Zustand mit Symbol, Text und optionaler Aktion.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: mf.accentSoft,
                    borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, color: mf.accent, size: 30),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: mf.text)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mf.textMuted, height: 1.5)),
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "vor 5 Min.", "gestern", "12.03.2026"
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'gerade eben';
  if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
  if (d.inHours < 24) return 'vor ${d.inHours} Std.';
  if (d.inDays == 1) return 'gestern';
  if (d.inDays < 7) return 'vor ${d.inDays} Tagen';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}';
}

/// Einfacher Eingabedialog für Titel.
Future<String?> askText(BuildContext context,
    {required String title,
    String initial = '',
    String hint = '',
    String confirm = 'Speichern',
    bool multiline = false}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: multiline ? null : (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(confirm)),
      ],
    ),
  );
}
