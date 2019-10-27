import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';

// This is written for the TTS server at http://software.hixie.ch/utilities/unix/home-tools/tts.dart

class TextToSpeechServer {
  TextToSpeechServer({ @required this.host, @required this.password, this.onLog });

  final String host;
  final String password;

  final LogCallback onLog;

  static const Duration kRetryDelay = const Duration(seconds: 5);
  static const Duration kMaxLatency = const Duration(seconds: 1);
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
    Completer<WebSocket> completer;
    Stopwatch stopwatch = new Stopwatch()
      ..start();
    do {
      try {
        completer = new Completer<WebSocket>();
        _connectionProgress = completer.future;
        _messageIndex = 0;
        _connection = await WebSocket.connect(host);
      } on SocketException catch (error) {
        _log('failed to contact tts deamon: $error');
        await new Future<Null>.delayed(kRetryDelay);
        _connection = null;
      }
    } while (_connection == null);
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

  Future<Null> _send(String message, { Duration timeout: kMaxLatency }) async {
    Stopwatch stopwatch = new Stopwatch()
      ..start();
    WebSocket socket = await _connect()
      .timeout(timeout, onTimeout: () {
        _log('timed out trying to contact tts daemon after ${prettyDuration(timeout)}');
        return null;
      });
    if (socket == null)
      return;
    _messageIndex += 1;
    socket.add(message);
    _pending[_messageIndex] = new Completer<Null>();
    await _pending[_messageIndex].future;
  }

  Future<Null> speak(String message, { Duration timeout: kMaxLatency }) async {
    assert(!message.contains('\0'));
    assert(timeout != null);
    await _send('$password\0speak\0$message', timeout: timeout);
  }

  Future<Null> alarm(int level, { Duration timeout: kMaxLatency }) async {
    assert(level >= 1 && level <= 9);
    assert(timeout != null);
    await _send('$password\0alarm\0$level', timeout: timeout);
  }

  Future<Null> audioIcon(String name, { Duration timeout: kMaxLatency }) async {
    assert(name != null);
    assert(timeout != null);
    await _send('$password\0audio-icon\0$name', timeout: timeout);
  }

  Future<Null> increaseVolume({ Duration timeout: kMaxLatency }) async {
    assert(timeout != null);
    await _send('$password\0increase-volume', timeout: timeout);
  }

  Future<Null> decreaseVolume({ Duration timeout: kMaxLatency }) async {
    assert(timeout != null);
    await _send('$password\0decrease-volume', timeout: timeout);
  }

  Future<Null> setVolume(double volume, { Duration timeout: kMaxLatency }) async {
    assert(volume >= 0.0);
    assert(volume <= 1.0);
    assert(timeout != null);
    await _send('$password\0set-volume\0$volume', timeout: timeout);
  }

  void _log(String message) {
    if (onLog != null)
      onLog(message);
  }
}
