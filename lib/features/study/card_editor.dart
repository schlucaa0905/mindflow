import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../data/card_generator.dart';
import '../../data/models.dart';
import '../../data/study_repository.dart';
import '../../ui/futuristic.dart';

/// Karteikarte anlegen oder bearbeiten. Beim Anlegen kann man mit
/// „Speichern & nächste“ schnell mehrere Karten hintereinander erstellen.
Future<void> editFlashcard(BuildContext context,
    {String? entryId, Flashcard? card}) async {
  final study = Services.of(context).study;
  final front = TextEditingController(text: card?.front ?? '');
  final back = TextEditingController(text: card?.back ?? '');
  final frontFocus = FocusNode();
  var created = 0;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final mf = ctx.mf;
      bool valid() =>
          front.text.trim().isNotEmpty && back.text.trim().isNotEmpty;
      void save({required bool next}) {
        if (!valid()) return;
        if (card == null) {
          study.create(
              front: front.text, back: back.text, entryId: entryId);
          created++;
        } else {
          study.edit(card.id, front: front.text, back: back.text);
        }
        if (next) {
          front.clear();
          back.clear();
          setState(() {});
          frontFocus.requestFocus();
        } else {
          Navigator.pop(ctx);
        }
      }

      return AlertDialog(
        title: Text(card == null ? 'Neue Karteikarte' : 'Karte bearbeiten'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VORDERSEITE · FRAGE',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: mf.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: front,
                focusNode: frontFocus,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(hintText: 'z. B. Was macht DHCP?'),
              ),
              const SizedBox(height: 16),
              Text('RÜCKSEITE · ANTWORT',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: mf.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: back,
                minLines: 3,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'Vergibt IP-Adressen automatisch im Netzwerk.'),
              ),
              if (created > 0) ...[
                const SizedBox(height: 12),
                StatusPill('$created ${created == 1 ? 'Karte' : 'Karten'} erstellt',
                    color: mf.success),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(created > 0 ? 'Fertig' : 'Abbrechen')),
          if (card == null)
            OutlinedButton(
                onPressed: valid() ? () => save(next: true) : null,
                child: const Text('Speichern & nächste')),
          FilledButton(
              onPressed: valid() ? () => save(next: false) : null,
              child: const Text('Speichern')),
        ],
      );
    }),
  );
  // Nicht sofort freigeben: Der Dialog blendet noch aus und benutzt die
  // Felder dabei weiter. Der Speicher wird automatisch aufgeräumt.
}

/// Schlägt Karten aus dem Text eines Wissenseintrags vor und legt die
/// ausgewählten an. Gibt die Anzahl erstellter Karten zurück.
Future<int> generateCardsFromEntry(BuildContext context, MfObject entry) async {
  final study = Services.of(context).study;
  final existing = {for (final c in study.cardsOf(entry.id)) c.front};
  final drafts = cardsFromText(entry.body, skipFronts: existing);
  if (drafts.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keine Vorschläge gefunden'),
        content: const SizedBox(
          width: 440,
          child: Text(
            'Schreib im Text eine Zeile pro Begriff, zum Beispiel:\n\n'
            'DHCP: vergibt IP-Adressen automatisch\n'
            'DNS – übersetzt Namen in IP-Adressen\n\n'
            'Daraus entstehen dann automatisch Karteikarten.',
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return 0;
  }
  final chosen = List<bool>.filled(drafts.length, true);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final mf = ctx.mf;
      final count = chosen.where((x) => x).length;
      return AlertDialog(
        title: const Text('Karten aus dem Text'),
        content: SizedBox(
          width: 520,
          height: 380,
          child: ListView.builder(
            itemCount: drafts.length,
            itemBuilder: (ctx, i) => CheckboxListTile(
              value: chosen[i],
              onChanged: (v) => setState(() => chosen[i] = v ?? false),
              title: Text(drafts[i].front,
                  style: TextStyle(fontWeight: FontWeight.w600, color: mf.text)),
              subtitle: Text(drafts[i].back,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mf.textMuted)),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: count == 0 ? null : () => Navigator.pop(ctx, true),
              child: Text('$count ${count == 1 ? 'Karte' : 'Karten'} erstellen')),
        ],
      );
    }),
  );
  if (ok != true) return 0;
  var n = 0;
  for (var i = 0; i < drafts.length; i++) {
    if (!chosen[i]) continue;
    study.create(front: drafts[i].front, back: drafts[i].back, entryId: entry.id);
    n++;
  }
  return n;
}
