import 'package:flutter/services.dart';

final _listItem = RegExp(r'^(\s*)(•|-|\d+\.)\s');

/// Setzt Listen beim Tippen fort – wie in jeder guten Notiz-App:
/// Enter nach „• Punkt“ beginnt mit „• “, nach „3. Punkt“ mit „4. “.
/// Enter in einem leeren Listenpunkt beendet die Liste.
class ListContinuationFormatter extends TextInputFormatter {
  const ListContinuationFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final cursor = newValue.selection.baseOffset;
    // Nur genau ein neu getipptes Enter direkt vor dem Cursor.
    if (!newValue.selection.isCollapsed ||
        text.length != oldValue.text.length + 1 ||
        cursor < 1 ||
        cursor > text.length ||
        text[cursor - 1] != '\n') {
      return newValue;
    }
    final lineStart = cursor < 2 ? 0 : text.lastIndexOf('\n', cursor - 2) + 1;
    final prevLine = text.substring(lineStart, cursor - 1);
    final m = _listItem.firstMatch(prevLine);
    if (m == null) return newValue;
    // Leerer Listenpunkt: Liste beenden (Zeichen und Enter entfernen).
    if (prevLine.trim() == m.group(2)) {
      final cleaned = text.replaceRange(lineStart, cursor, '');
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    var marker = m.group(2)!;
    if (marker.endsWith('.')) {
      final n = int.tryParse(marker.substring(0, marker.length - 1)) ?? 0;
      marker = '${n + 1}.';
    }
    final prefix = '${m.group(1)}$marker ';
    return TextEditingValue(
      text: text.replaceRange(cursor, cursor, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
  }
}

/// Macht aus allen Zeilen Aufzählungspunkte – oder entfernt sie wieder.
String toggleBullets(String text) {
  if (text.trim().isEmpty) return '• ';
  final lines = text.split('\n');
  final filled = lines.where((l) => l.trim().isNotEmpty).toList();
  final allBullets =
      filled.isNotEmpty && filled.every((l) => l.trimLeft().startsWith('• '));
  return [
    for (final l in lines)
      if (l.trim().isEmpty)
        l
      else if (allBullets)
        l.replaceFirst('• ', '')
      else if (l.trimLeft().startsWith('• '))
        l
      else
        '• $l'
  ].join('\n');
}
