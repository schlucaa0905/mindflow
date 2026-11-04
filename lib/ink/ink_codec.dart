import 'dart:convert';
import 'dart:typed_data';

import 'stroke.dart';

/// Kompaktes Binärformat für Striche (.mfink).
///
/// Aufbau (Little Endian):
///   Kopf:   'MFNK' (u32) | Version (u16) | reserviert (u16) | Anzahl (u32)
///   Strich: ID-Länge (u16) | ID (UTF-8) | Farbe (u32) | Breite (f32)
///           | Werkzeug (u8) | Flags (u8: Bit 0 gelöscht, Bit 1 Füllung)
///           | [Füllfarbe (u32), nur mit Bit 1] | Anzahl Werte (u32)
///           | Werte (f32 × n, je x,y,druck)
///
/// Gelöschte Striche bleiben als "Grabstein" erhalten – das braucht die
/// spätere Synchronisation, um Löschungen auf andere Geräte zu übertragen.
const int kInkMagic = 0x4B4E464D; // 'MFNK' als Little-Endian-Bytes
const int kInkVersion = 1;

Uint8List encodeInk(List<Stroke> strokes) {
  var size = 12;
  final ids = <Uint8List>[];
  for (final s in strokes) {
    final id = utf8.encode(s.id);
    if (id.length > 0xFFFF) throw ArgumentError('Strich-ID zu lang');
    ids.add(id);
    size += 2 + id.length + 4 + 4 + 1 + 1 + 4 + s.points.length * 4;
    if (s.fill != null) size += 4;
  }

  final data = ByteData(size);
  const le = Endian.little;
  var o = 0;
  data.setUint32(o, kInkMagic, le);
  o += 4;
  data.setUint16(o, kInkVersion, le);
  o += 2;
  data.setUint16(o, 0, le);
  o += 2;
  data.setUint32(o, strokes.length, le);
  o += 4;

  for (var i = 0; i < strokes.length; i++) {
    final s = strokes[i];
    final id = ids[i];
    data.setUint16(o, id.length, le);
    o += 2;
    for (final b in id) {
      data.setUint8(o++, b);
    }
    data.setUint32(o, s.color, le);
    o += 4;
    data.setFloat32(o, s.width, le);
    o += 4;
    data.setUint8(o++, s.tool.index);
    data.setUint8(o++, (s.deleted ? 1 : 0) | (s.fill != null ? 2 : 0));
    if (s.fill != null) {
      data.setUint32(o, s.fill!, le);
      o += 4;
    }
    data.setUint32(o, s.points.length, le);
    o += 4;
    for (final v in s.points) {
      data.setFloat32(o, v, le);
      o += 4;
    }
  }
  return data.buffer.asUint8List();
}

/// Liest Striche. Wirft [FormatException], wenn die Datei beschädigt ist.
List<Stroke> decodeInk(Uint8List bytes) {
  try {
    return _decode(bytes);
  } on RangeError {
    throw const FormatException('Tinten-Datei ist abgeschnitten oder beschädigt');
  }
}

List<Stroke> _decode(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  const le = Endian.little;
  var o = 0;
  if (data.lengthInBytes < 12 || data.getUint32(0, le) != kInkMagic) {
    throw const FormatException('Keine MindFlow-Tinten-Datei');
  }
  o += 4;
  final version = data.getUint16(o, le);
  o += 4; // Version + reserviert
  if (version > kInkVersion) {
    throw FormatException('Unbekannte Dateiversion $version');
  }
  final count = data.getUint32(o, le);
  o += 4;

  final result = <Stroke>[];
  for (var i = 0; i < count; i++) {
    final idLen = data.getUint16(o, le);
    o += 2;
    final id = utf8.decode(Uint8List.sublistView(bytes, o, o + idLen));
    o += idLen;
    final color = data.getUint32(o, le);
    o += 4;
    final width = data.getFloat32(o, le);
    o += 4;
    final toolIndex = data.getUint8(o++);
    final flags = data.getUint8(o++);
    final deleted = flags & 1 == 1;
    int? fill;
    if (flags & 2 == 2) {
      fill = data.getUint32(o, le);
      o += 4;
    }
    final n = data.getUint32(o, le);
    o += 4;
    if (n % 3 != 0 || toolIndex >= InkTool.values.length) {
      throw const FormatException('Ungültiger Strich in Tinten-Datei');
    }
    final pts = Float32List(n);
    for (var j = 0; j < n; j++) {
      pts[j] = data.getFloat32(o, le);
      o += 4;
    }
    result.add(Stroke(
      id: id,
      color: color,
      width: width,
      tool: InkTool.values[toolIndex],
      points: pts,
      deleted: deleted,
      fill: fill,
    ));
  }
  return result;
}
