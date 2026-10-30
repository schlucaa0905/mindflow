import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Ein Eintrag im Menü – oder eine Trennlinie ([CleanMenuEntry.divider]).
class CleanMenuEntry {
  const CleanMenuEntry(
    this.value,
    this.label, {
    this.icon,
    this.subtitle,
    this.destructive = false,
    this.checked = false,
  });

  const CleanMenuEntry.divider()
      : value = null,
        label = '',
        icon = null,
        subtitle = null,
        destructive = false,
        checked = false;

  /// null = Trennlinie.
  final String? value;
  final String label;
  final IconData? icon;
  final String? subtitle;

  /// Rot dargestellt (z. B. Löschen).
  final bool destructive;

  /// Mit Häkchen (z. B. eingeschaltete Option).
  final bool checked;

  bool get isDivider => value == null;
}

/// Schlichtes, modernes Menü: abgerundet, mit Symbolen und Gruppen.
/// Ersetzt die Standard-Dropdowns überall in der App.
class CleanMenuButton extends StatefulWidget {
  const CleanMenuButton({
    super.key,
    required this.entries,
    required this.onSelected,
    this.icon = Icons.more_horiz,
    this.tooltip = 'Mehr',
    this.iconColor,
    this.size = 38,
    this.trigger,
  });

  /// Eigener Auslöser statt des Symbols (z. B. „125 % ▾“).
  final Widget? trigger;

  final List<CleanMenuEntry> entries;
  final ValueChanged<String> onSelected;
  final IconData icon;
  final String tooltip;
  final Color? iconColor;
  final double size;

  @override
  State<CleanMenuButton> createState() => _CleanMenuButtonState();
}

class _CleanMenuButtonState extends State<CleanMenuButton> {
  final MenuController _ctrl = MenuController();

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    return MenuAnchor(
      controller: _ctrl,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(mf.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(14),
        shadowColor: const WidgetStatePropertyAll(Color(0x40000000)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: mf.border.withValues(alpha: 0.7)),
        )),
      ),
      menuChildren: [
        for (final e in widget.entries)
          if (e.isDivider)
            Container(
              height: 1,
              width: 248,
              margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              color: mf.border.withValues(alpha: 0.7),
            )
          else
            _MenuRow(
              entry: e,
              onTap: () {
                _ctrl.close();
                widget.onSelected(e.value!);
              },
            ),
      ],
      builder: (context, ctrl, _) => Tooltip(
        message: widget.tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
          child: widget.trigger ??
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: Icon(widget.icon,
                    size: 20, color: widget.iconColor ?? mf.text),
              ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.entry, required this.onTap});

  final CleanMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mf = context.mf;
    final color = entry.destructive ? mf.danger : mf.text;
    return SizedBox(
      width: 268,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: entry.destructive
                      ? mf.danger.withValues(alpha: 0.10)
                      : mf.surfaceRaised,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(entry.icon ?? Icons.circle_outlined,
                    size: 17, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: color)),
                    if (entry.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(entry.subtitle!,
                            style:
                                TextStyle(fontSize: 12, color: mf.textMuted)),
                      ),
                  ],
                ),
              ),
              if (entry.checked)
                Icon(Icons.check_rounded, size: 18, color: mf.accent),
            ],
          ),
        ),
      ),
    );
  }
}
