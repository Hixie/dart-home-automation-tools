import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

// This is written for the TTS server at http://software.hixie.ch/utilities/unix/home-tools/tts.dart

class TextToSpeechServer {
  TextToSpeechServer({ @required this.host, @required this.password });

  final String host;
  final String password;

  static const String kCompleted = 'completed ';

  Map<int, Completer<Null>> _pending = <int, Completer<Null>>{};

  WebSocket _connection;
  Future<WebSocket> _connectionProgress;
  int _messageIndex = 0;
  Future<WebSocket> _connect() async {
    if (_connection != null)
      return _connection;
    if (_connectionProgress != null)
      return _connectionProgress;
    Completer<WebSocket> completer = new Completer<WebSocket>();
    _connectionProgress = completer.future;
    _messageIndex = 0;
    _connection = await WebSocket.connect(host);
    _connection.listen((dynamic message) {
      if (message is String) {
        if (!message.startsWith(kCompleted))
          return;
        int handle = int.parse(message.substring(kCompleted.length), onError: (String source) => 0);
        if (_pending.containsKey(handle)) {
          _pending[handle].complete();
          _pending.remove(handle);
        }
      }
    });
    _connection.done.then((WebSocket socket) {
      _connection = null;
      for (Completer<Null> completer in _pending.values)
        completer.complete();
      _pending.clear();
    });
    completer.complete(_connection);
    _connectionProgress = null;
    return _connection;
  }

  void dispose() {
    _connection?.close(WebSocketStatus.GOING_AWAY);
  }

  Future<Null> _send(String message) async {
    WebSocket socket = await _connect();
    _messageIndex += 1;
    socket.add(message);
    _pending[_messageIndex] = new Completer<Null>();
    await _pending[_messageIndex].future;
  }

  Future<Null> speak(String message) async {
    assert(!message.contains('\0'));
    await _send('$password\0speak\0$message');
  }

  Future<Null> alarm(int level) async {
    assert(level >= 1 && level <= 9);
    await _send('$password\0alarm\0$level');
  }

  Future<Null> increaseVolume() async {
    await _send('$password\0increase-volume');
  }

  Future<Null> decreaseVolume() async {
    await _send('$password\0decrease-volume');
  }

  Future<Null> setVolume(double volume) async {
    assert(volume >= 0.0);
    assert(volume <= 1.0);
    await _send('$password\0set-volume\0$volume');
  }
}
