import 'dart:collection';
import 'dart:typed_data';

class PacketBuffer {
  PacketBuffer();

  final Queue<Uint8List> _buffer = Queue<Uint8List>();

  int _start = 0; // index of last checkpoint
  int _cursor = 0; // index of end of last read
  int _length = 0; // total bytes allocated

  /// Adds [data] to the end of the buffer.
  /// Increments [available] by the length of [data].
  void add(Uint8List data) {
    _buffer.add(data);
    _length += data.length;
    assert(
      _buffer.fold<int>(
            0,
            (int current, Uint8List next) => current + next.length,
          ) ==
          _length,
    );
  }

  /// Returns the number of unread bytes.
  int get available {
    assert(
      _buffer.fold<int>(
            0,
            (int current, Uint8List next) => current + next.length,
          ) ==
          _length,
    );
    return _length - _cursor;
  }

  /// Marks all bytes as unread.
  void rewind() {
    _cursor = _start;
  }

  /// Reads the first 8 unread bytes, and returns them as an integer.
  /// Marks those bytes as read and decrements [available] by 8.
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
        _flatten();
        bytes = _buffer.single;
        packetOffset = _cursor;
      }
      _cursor += 8;
      return bytes.buffer.asByteData().getUint64(packetOffset);
    }
    throw StateError('Unreachable.');
  }

  /// Reads the first [length] unread bytes, and returns them as an [Uint8List].
  /// Marks those bytes as read and decrements [available] by [length].
  Uint8List readUint8List(int length) {
    assert(length <= available); // contract
    assert(_start < _buffer.first.length); // invariant
    if (length == 0) {
      return Uint8List(0);
    }
    int packetOffset = _cursor;
    for (Uint8List packet in _buffer) {
      if (packetOffset >= packet.length) {
        packetOffset -= packet.length;
        continue;
      }
      // We found the start of the list of bytes.
      Uint8List bytes;
      if (packetOffset + length <= packet.length) {
        bytes = packet;
      } else {
        // the bytes stradle a boundary
        _flatten();
        bytes = _buffer.single;
        packetOffset = _cursor;
      }
      _cursor += length;
      return bytes.buffer
          .asUint8List(bytes.offsetInBytes + packetOffset, length);
    }
    throw StateError('Unreachable.');
  }

  void _flatten() {
    Uint8List bytes = Uint8List(_length - _start);
    _length = bytes.length;
    _cursor -= _start;
    int index = 0;
    for (Uint8List packet in _buffer) {
      if (_start > 0) {
        bytes.setRange(
          index,
          index + (packet.length - _start),
          packet.buffer.asUint8List(
            packet.offsetInBytes + _start,
            packet.length - _start,
          ),
        );
        index += packet.length - _start;
        _start = 0;
      } else {
        bytes.setRange(index, index + packet.length, packet);
        index += packet.length;
      }
    }
    _buffer.clear();
    _buffer.add(bytes);
    assert(_start == 0);
    assert(_cursor <= _buffer.first.length);
  }

  /// Forgets all bytes marked as read.
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
