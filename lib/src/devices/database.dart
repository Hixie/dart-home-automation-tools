import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../packet_buffer.dart';
import '../table_record.dart';

const bool _verbose = false;

class DatabaseStreamingClient {
  DatabaseStreamingClient(this.hostName, this.port, this.securityContext, this.tableId, this.recordSize) {
    _controller = StreamController<TableRecord>(onListen: _listen, onCancel: _cancel);
  }

  final String hostName;
  final int port;
  final SecurityContext securityContext;
  final int tableId;
  final int recordSize;

  int get rawRecordSize => 8 + recordSize + 8; // timestamp + record + checksum

  StreamController<TableRecord> _controller;
  Stream<TableRecord> get stream => _controller.stream;

  Socket _socket;

  void _listen() {
    _socket = null;
    if (!_controller.hasListener)
      return; // socket was probably disconnected because _cancel closed it
    Future<Socket> socket = SecureSocket.connect(hostName, port, context: securityContext);
    socket.then((Socket socket) async {
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      ByteData request = ByteData(16);
      request.setUint64(0, tableId);
      request.setUint64(8, 0x00); // streaming request
      socket.add(request.buffer.asUint8List());
      socket.flush();
      final PacketBuffer buffer = PacketBuffer();
      await for (Uint8List packet in socket) {
        buffer.add(packet);
        while (buffer.available >= rawRecordSize) {
          _controller.add(TableRecord.fromRaw(buffer.readUint8List(rawRecordSize)));
          buffer.checkpoint();
        }
      }
    }).catchError((Object error, StackTrace stack) {
      // ignore all errors
      if (_verbose)
        print('$runtimeType: $error\n$stack');
    }).whenComplete(_listen);
  }

  void _cancel() {
    _socket?.close();
  }
}

Stream<TableRecord> fetchHistoricalData(String hostName, int port, SecurityContext securityContext, int tableId, int recordSize, DateTime start, DateTime end, Duration resolution) async* {
  final int rawRecordSize = 8 + recordSize + 8; // timestamp + record + checksum
  Socket socket = await SecureSocket.connect(hostName, port, context: securityContext);
  ByteData request = ByteData(8 * 5);
  request.setUint64(0, tableId);
  request.setUint64(8, 0x01); // read
  request.setUint64(16, start.toUtc().millisecondsSinceEpoch);
  request.setUint64(24, end.toUtc().millisecondsSinceEpoch);
  request.setUint64(32, resolution.inMilliseconds);
  socket.add(request.buffer.asUint8List());
  socket.flush();
  final PacketBuffer buffer = PacketBuffer();
  await for (Uint8List packet in socket) {
    buffer.add(packet);
    while (buffer.available >= rawRecordSize) {
      try {
        yield TableRecord.fromRaw(buffer.readUint8List(rawRecordSize));
      } catch (error, stack) {
        print('got $error\n$stack');
      }
      buffer.checkpoint();
    }
  }
  print('done with reading...');
}