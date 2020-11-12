import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../packet_buffer.dart';
import '../table_record.dart';

class DatabaseStreamingClient {
  DatabaseStreamingClient(this.hostName, this.port, this.securityContext, this.tableId, this.recordSize) {
    _controller = StreamController(onListen: _listen, onCancel: _cancel);
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
      request.setUint64(8, 0); // streaming request
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
      // terminate.completeError(error, stack);
    }).whenComplete(_listen);
  }

  void _cancel() {
    _socket?.close();
  }
}
