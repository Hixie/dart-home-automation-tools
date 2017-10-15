import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

// This is written for the TTS server at http://software.hixie.ch/utilities/unix/home-tools/tts.dart

class TextToSpeechServer {
  TextToSpeechServer({ @required this.host, @required this.password });

  final String host;
  final String password;

  WebSocket _connection;
  Future<WebSocket> _connect() async {
    if (_connection != null)
      return _connection;
    _connection = await WebSocket.connect(host);
    _connection.done.then((Null value) {
      _connection = null;
    });
    return _connection;
  }

  void dispose() {
    _connection?.close(WebSocketStatus.GOING_AWAY);
  }

  Future<Null> speak(String message) async {
    assert(!message.contains('\0'));
    await _connect()
      ..add('$password\0speak\0$message');
  }

  Future<Null> increaseVolume() async {
    await _connect()
      ..add('$password\0increase-volume');
  }

  Future<Null> decreaseVolume() async {
    await _connect()
      ..add('$password\0decrease-volume');
  }

  Future<Null> setVolume(double volume) async {
    assert(volume >= 0.0);
    assert(volume <= 1.0);
    await _connect()
      ..add('$password\0set-volume\0$volume');
  }
}
