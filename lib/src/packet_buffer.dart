import 'dart:collection';
import 'dart:typed_data';

class PacketBuffer {
  PacketBuffer();

  final Queue<Uint8List> _buffer = Queue<Uint8List>();

  int _start = 0;
  int _cursor = 0;
  int _length = 0;

  void add(Uint8List data) {
    _buffer.add(data);
    _length += data.length;
  }

  int get available {
    assert(_buffer.fold<int>(0, (int current, Uint8List next) => current + next.length) == _length);
    return _length - _cursor;
  }

  void rewind() {
    _cursor = _start;
  }

  int readInt64() {
    assert(available >= 8); // contract
    assert(_start < _buffer.first.length); // invariant
    int packetOffset = _cursor;
    for (Uint8List packet in _buffer) {
      if (packetOffset >= packet.length) {
        packetOffset -= packet.length;
        continue;
      }
      // We found the start of the int.
      Uint8List bytes;
      if (packetOffset + 8 <= packet.length) {
        bytes = packet;
      } else {
        // the int stradles the boundary
        flatten();
        bytes = _buffer.single;
        packetOffset = _cursor;
      }
      _cursor += 8;
      return bytes.buffer.asByteData().getUint64(packetOffset);
    }
    throw StateError('Unreachable.');
  }

  Uint8List readUint8List(int length) {
    assert(length <= available); // contract
    assert(_start < _buffer.first.length); // invariant
    int packetOffset = _cursor;
    for (Uint8List packet in _buffer) {
      if (packetOffset > packet.length) {
        packetOffset -= packet.length;
        continue;
      }
      // We found the start of the list of bytes.
      Uint8List bytes;
      if (packetOffset + length <= packet.length) {
        bytes = packet;
      } else {
        // the bytes stradle a boundary
        flatten();
        bytes = _buffer.single;
        packetOffset = _cursor;
      }
      _cursor += length;
      return bytes.buffer.asUint8List(bytes.offsetInBytes + packetOffset, length);
    }
    throw StateError('Unreachable.');
  }

  void flatten() {
    Uint8List bytes = Uint8List(available);
    _length = bytes.length;
    _cursor -= _start;
    int index = 0;
    for (Uint8List packet in _buffer) {
      if (_start > 0) { 
        bytes.setRange(index, index + packet.length - _start, packet.buffer.asUint8List(packet.offsetInBytes + _start, packet.length));
        _start = 0;
      } else {
        bytes.setRange(index, index + packet.length, packet);
      }
    }
    _buffer.clear();
    _buffer.add(bytes);
    assert(_start == 0);
    assert(_cursor <= _buffer.first.length);
  }

  void checkpoint() {
    _start = _cursor;
    while (_buffer.isNotEmpty && _buffer.first.length <= _start) {
      _start -= _buffer.first.length;
      _cursor -= _buffer.first.length;
      _length -= _buffer.first.length;
      _buffer.removeFirst();
    }
    assert((_buffer.isEmpty && _start == 0) || (_start < _buffer.first.length));
  }
}
