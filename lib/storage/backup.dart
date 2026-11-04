import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/object_repository.dart';

/// Datensicherung: alles (Datenbank, Handschrift, PDFs, Bilder) als eine
/// ZIP-Datei – zum Ablegen in iCloud Drive, auf dem PC oder per Mail.
class Backup {
  static Future<Directory> _base() async =>
      Directory((await getApplicationSupportDirectory()).path);

  static final String _sep = Platform.pathSeparator;

  /// Erstellt die Sicherung und öffnet „Teilen/Sichern unter“.
  /// [origin]: Stelle des Knopfs (nötig für das Teilen-Fenster auf dem iPad).
  static Future<void> export(Database db, Rect origin) async {
    final tmp = await getTemporaryDirectory();
    final out = await _write(db, tmp.path);
    await Share.shareXFiles([XFile(out.path)],
        subject: 'MindFlow-Sicherung', sharePositionOrigin: origin);
  }

  /// Schreibt die Sicherungs-ZIP in den Ordner [dir] (im Hintergrund,
  /// damit die App flüssig bleibt) und gibt die Datei zurück.
  static Future<File> _write(Database db, String dir) async {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final root = '${(await _base()).path}${_sep}mindflow';
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final path = '$dir${_sep}MindFlow-Sicherung-'
        '${d.year}-${two(d.month)}-${two(d.day)}.zip';
    final sep = _sep;
    await Isolate.run(() {
      final archive = Archive();
      final rootDir = Directory(root);
      for (final f in rootDir.listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(root.length + 1).replaceAll(sep, '/');
        if (rel.endsWith('-wal') || rel.endsWith('-shm')) continue;
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(ZipEncoder().encode(archive), flush: true);
    });
    return File(path);
  }

  /// Ordner „Sicherungen“ – in der Dateien-App unter „Auf meinem iPad ›
  /// MindFlow“ sichtbar.
  static Future<Directory> autoDir() async => Directory(
      '${(await getApplicationDocumentsDirectory()).path}${_sep}Sicherungen');

  /// Automatische Sicherung: alle [days] Tage eine ZIP in [autoDir],
  /// die neuesten [keep] bleiben. Gibt die neue Datei zurück (oder null,
  /// wenn noch keine fällig war). [force]: sofort sichern.
  static Future<File?> auto(Database db,
      {required int days,
      required DateTime? last,
      bool force = false,
      int keep = 3}) async {
    if (!force &&
        (days <= 0 ||
            (last != null && DateTime.now().difference(last).inDays < days))) {
      return null;
    }
    final dir = await autoDir();
    await dir.create(recursive: true);
    final out = await _write(db, dir.path);
    final old = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(keep)) {
      f.deleteSync();
    }
    return out;
  }

  /// Automatische Sicherung nach den Einstellungen (`autoBackupDays`,
  /// Standard 7; 0 = aus). Fehler werden still übergangen.
  static Future<File?> runAuto(Database db, ObjectRepository repo,
      {bool force = false}) async {
    final days = int.tryParse(repo.setting('autoBackupDays') ?? '') ?? 7;
    final last = DateTime.tryParse(repo.setting('lastAutoBackup') ?? '');
    try {
      final f = await auto(db, days: days, last: last, force: force);
      if (f != null) {
        repo.setSetting('lastAutoBackup', DateTime.now().toIso8601String());
      }
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Liest eine Sicherung ein. Übernommen wird sie beim nächsten Start.
  /// Gibt false zurück, wenn abgebrochen; wirft bei ungültiger Datei.
  static Future<bool> prepareRestore() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'MindFlow-Sicherung',
          extensions: ['zip'],
          uniformTypeIdentifiers: ['public.zip-archive']),
    ]);
    if (f == null) return false;
    final archive = ZipDecoder().decodeBytes(await f.readAsBytes());
    if (!archive.files.any((e) => e.name == 'mindflow.db')) {
      throw const FormatException('Das ist keine MindFlow-Sicherung.');
    }
    final staging = Directory('${(await _base()).path}${_sep}mindflow_restore');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    for (final e in archive.files) {
      if (!e.isFile || e.name.contains('..')) continue;
      final out = File('${staging.path}$_sep${e.name.replaceAll('/', _sep)}');
      await out.create(recursive: true);
      await out.writeAsBytes(e.content, flush: true);
    }
    return true;
  }

  /// Beim App-Start (vor dem Öffnen der Datenbank): vorbereitete
  /// Wiederherstellung übernehmen. Die alten Daten werden ersetzt.
  static Future<void> applyPending() async {
    final base = (await _base()).path;
    final staging = Directory('$base${_sep}mindflow_restore');
    if (!staging.existsSync() ||
        !File('${staging.path}${_sep}mindflow.db').existsSync()) {
      return;
    }
    final current = Directory('$base${_sep}mindflow');
    final old = Directory('$base${_sep}mindflow_old');
    if (old.existsSync()) old.deleteSync(recursive: true);
    if (current.existsSync()) current.renameSync(old.path);
    staging.renameSync(current.path);
    if (old.existsSync()) old.deleteSync(recursive: true);
  }
}
