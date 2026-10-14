import 'dart:convert';
import 'dart:typed_data';

/// Reads local Steam appinfo v39–v41. Never interprets directory names as types.
class SteamAppInfo {
  static Map<int, String> types(Uint8List bytes) {
    final reader = _Reader(bytes);
    final magic = reader.u32();
    if (magic < 0x07564427 || magic > 0x07564429) {
      throw const FormatException('Unsupported Steam appinfo version');
    }
    reader.u32(); // Universe
    final strings = <String>[];
    var dataEnd = bytes.length;
    if (magic == 0x07564429) {
      final offset = reader.u64();
      final entriesStart = reader.position;
      if (offset < entriesStart || offset >= bytes.length) {
        throw const FormatException('Invalid appinfo string table');
      }
      dataEnd = offset;
      reader.position = offset;
      final count = reader.u32();
      if (count > bytes.length) {
        throw const FormatException('Invalid key count');
      }
      for (var i = 0; i < count; i++) {
        strings.add(reader.string());
      }
      reader.position = entriesStart;
    }
    final result = <int, String>{};
    while (reader.position < dataEnd) {
      final id = reader.u32();
      if (id == 0) break;
      final size = reader.u32();
      final end = reader.position + size;
      final headerSize = magic >= 0x07564428 ? 60 : 40;
      if (end > dataEnd || size < headerSize) {
        throw const FormatException('Invalid appinfo entry length');
      }
      reader.position += headerSize;
      reader.limit = end;
      final tree = reader.object(magic == 0x07564429 ? strings : null, 0);
      final info = tree['appinfo'];
      final common = info is Map ? info['common'] : null;
      final type = common is Map ? common['type'] : null;
      if (type is String) result[id] = type.toLowerCase();
      reader.limit = bytes.length;
      reader.position = end;
    }
    return result;
  }
}

class _Reader {
  _Reader(this.bytes)
    : data = ByteData.sublistView(bytes),
      limit = bytes.length;
  final Uint8List bytes;
  final ByteData data;
  int position = 0, limit;
  void require(int count) {
    if (position + count > limit || count < 0) {
      throw const FormatException('Truncated Steam appinfo');
    }
  }

  int u32() {
    require(4);
    final value = data.getUint32(position, Endian.little);
    position += 4;
    return value;
  }

  int u64() {
    require(8);
    final value = data.getUint64(position, Endian.little);
    position += 8;
    return value;
  }

  String string() {
    final start = position;
    while (position < limit && bytes[position] != 0) {
      position++;
    }
    require(1);
    final result = utf8.decode(
      bytes.sublist(start, position),
      allowMalformed: true,
    );
    position++;
    return result;
  }

  Map<String, dynamic> object(List<String>? keys, int depth) {
    if (depth > 64) throw const FormatException('Excessive appinfo nesting');
    final result = <String, dynamic>{};
    while (true) {
      require(1);
      final type = bytes[position++];
      if (type == 8) return result;
      final String key;
      if (keys == null) {
        key = string();
      } else {
        final index = u32();
        if (index >= keys.length) {
          throw const FormatException('Invalid appinfo key');
        }
        key = keys[index];
      }
      switch (type) {
        case 0:
          result[key] = object(keys, depth + 1);
        case 1:
          result[key] = string();
        case 2 || 3 || 4 || 6:
          result[key] = u32();
        case 7 || 10:
          result[key] = u64();
        case 5:
          final codes = <int>[];
          while (true) {
            require(2);
            final code = data.getUint16(position, Endian.little);
            position += 2;
            if (code == 0) break;
            codes.add(code);
          }
          result[key] = String.fromCharCodes(codes);
        default:
          throw FormatException('Unsupported appinfo value $type');
      }
    }
  }
}
