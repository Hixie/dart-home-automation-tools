import 'dart:typed_data';

class ChecksumException implements Exception {
  ChecksumException();
}

class TableRecord {
  TableRecord(this.timestamp, this.data);

  TableRecord.now(this.data) : timestamp = DateTime.now().toUtc();

  factory TableRecord.fromRaw(Uint8List data) {
    ByteData view = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(view.getUint64(0), isUtc: true);
    int checksum = view.getUint64(data.length - 8);
    TableRecord result = TableRecord(timestamp, data.sublist(8, data.length - 8));
    if (result.checksum != checksum)
      throw ChecksumException();
    return result;
  }

  final DateTime timestamp;
  final Uint8List data;

  int get checksum {
    int hash = timestamp.microsecondsSinceEpoch;
    hash ^= hash >> 32;
    hash &= 0xffffffff;
    for (int byte in data) {
      hash += byte;
      hash += hash << 10;
      hash ^= hash >> 6;
      hash &= 0xffffffff;
    }
    hash += hash << 3;
    hash ^= hash >> 11;
    hash += hash << 15;
    hash &= 0xffffffff;
    return (hash << 16) | (0x55FF00000000FFAA);
  }

  int get size => 8 + data.length + 8;

  Uint8List _encoded;

  Uint8List encode() {
    if (_encoded != null)
      return _encoded;
    _encoded = Uint8List(size);
    ByteData view = _encoded.buffer.asByteData();
    view.setUint64(0, timestamp.microsecondsSinceEpoch);
    _encoded.setRange(8, 8 + data.length, data);
    view.setUint64(8 + data.length, checksum);
    return _encoded;
  }

  @override
  String toString() {
    StringBuffer buffer = StringBuffer();
    for (int index = 0; index < data.length; index += 1) {
      if (index > 0 && index % 8 == 0)
        buffer.write(' ');
      if (index > 0)
        buffer.write(' ');
      buffer.write(data[index].toRadixString(16).padLeft(2, "0"));
    }
    return buffer.toString();
  }
}
