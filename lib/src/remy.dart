import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'common.dart';

typedef void NotificationHandler(RemyNotification notification);
typedef void UiUpdateHandler(RemyUi ui);

class RemyButton {
  const RemyButton(this.id, this.classes, this.label);
  final String id;
  final Set<String> classes;
  final String label;
  @override
  String toString() => 'button $id: "$label" $classes';
}

class RemyNotification {
  const RemyNotification(this.label, this.classes, this.escalationLevel);
  final String label;
  final Set<String> classes;
  final int escalationLevel;
  @override
  String toString() => 'message: "$label" ($escalationLevel) $classes';
}

class RemyMessage extends RemyNotification {
  const RemyMessage(String label, Set<String> classes, int escalationLevel, this.buttons)
   : super(label, classes, escalationLevel);
  final List<RemyButton> buttons;
  @override
  String toString() => '${super.toString()} $buttons';
}

class RemyToDo {
  const RemyToDo(this.id, this.label, this.classes, this.level);
  final String id;
  final String label;
  final Set<String> classes;
  final int level;
  @override
  String toString() => 'todo $id: "$label" ($level) $classes';
}

class RemyUi {
  const RemyUi(this.buttons, this.messages, this.todos);
  final Set<RemyButton> buttons;
  final Set<RemyMessage> messages;
  final Set<RemyToDo> todos;
  @override
  String toString() => 'RemyUi:\n${messages.join("\n")}\n${todos.join("\n")}\n${buttons.join("\n")}';
}

class Remy {
  Remy({
    InternetAddress host,
    int port: 12549,
    @required this.username,
    @required this.password,
    this.onError,
    this.onNotification,
    this.onUiUpdate,
  }) {
    assert(port != null);
    _connect(host, port);
  }

  final String username;
  final String password;
  final ErrorHandler onError;
  final NotificationHandler onNotification;
  final UiUpdateHandler onUiUpdate;

  Socket _server;
  bool _closed = false;

  final List<String> _pendingMessages = <String>[];

  Future<Null> _connect(InternetAddress host, int port) async {
    do {
      try {
        if (host == null) {
          final List<InternetAddress> hosts = await InternetAddress.lookup('damowmow.com');
          if (hosts.isEmpty)
            throw new Exception('Cannot lookup Remy\'s internet address: no results');
          host = hosts.first;
        }
        _server = await Socket.connect(host, port);
        _server.encoding = UTF8;
        Stream<List<int>>_messages = _server.transform(_RemyMessageParser.getTransformer(3));
        if (onUiUpdate != null)
          _server.write('enable-ui\x00\x00\x00');
        while (_pendingMessages.isNotEmpty)
          _server.write(_pendingMessages.removeAt(0));
        await for (List<int> bytes in _messages)
          _handleMessage(bytes);
        _server.destroy();
        _server = null;
      } catch (error) {
        _server?.destroy();
        _server = null;
        if (onError != null)
          await onError(error);
      }
      await new Future<Null>.delayed(const Duration(seconds: 1));
    } while (!_closed);
  }

  void _handleMessage(List<int> bytes) {
    if (bytes.length == 0) {
      // pong
      return;
    }
    List<List<int>> parts = _nullSplit(bytes, 2).toList();
    if (UTF8.decode(parts[0]) == 'update') {
      if (onUiUpdate != null) {
        final Map<String, RemyButton> buttons = <String, RemyButton>{};
        final Set<RemyMessage> messages = new Set<RemyMessage>();
        final Set<RemyToDo> todos = new Set<RemyToDo>();
        for (List<int> entry in parts.skip(1)) {
          final List<String> data = _nullSplit(entry, 1).map/*<String>*/(UTF8.decode).toList();
          if (data.isEmpty) {
            onError(new Exception('invalid data packet from Remy (has empty entry in UI update): ${UTF8.decode(bytes)}'));
          } else if (data[0] == 'button') {
            if (data.length < 4) {
              onError(new Exception('invalid data packet from Remy (insufficient data in button packet): ${UTF8.decode(bytes)}'));
            } else if (buttons.containsKey(data[1])) {
              onError(new Exception('received duplicate button ID'));
            } else {
              buttons[data[1]] = new RemyButton(data[1], new Set<String>.from(data[2].split(' ')), data[3]);
            }
          } else if (data[0] == 'message') {
            if (data.length < 4) {
              onError(new Exception('invalid data packet from Remy (insufficient data in message packet): ${UTF8.decode(bytes)}'));
            } else {
              messages.add(new RemyMessage(
                data[1],
                new Set<String>.from(data[2].split(' ')),
                int.parse(
                  data[3],
                  onError: (String source) { onError(new Exception('unexpected "numeric" data from remy: $source')); }
                ),
                data.sublist(4).map/*<RemyButton>*/((String id) {
                  if (buttons.containsKey(id))
                    return buttons[id];
                  onError(new Exception('unknown button ID in message "${data[1]}" from Remy: $id'));
                  return null;
                }).where((RemyButton button) => button != null).toList(),
              ));
            }
          } else if (data[0] == 'todo') {
            if (data.length < 5) {
              onError(new Exception('invalid data packet from Remy (insufficient data in todo packet): ${UTF8.decode(bytes)}'));
            } else {
              todos.add(new RemyToDo(
                data[1],
                data[2],
                new Set<String>.from(data[3].split(' ')),
                int.parse(
                  data[4],
                  onError: (String source) { onError(new Exception('unexpected "numeric" data from remy: $source')); }
                ),
              ));
            }
          } else {
            onError(new Exception('unexpected data from remy: ${UTF8.decode(bytes)}'));
          }
        }
        onUiUpdate(new RemyUi(
          new Set<RemyButton>.from(buttons.values),
          messages,
          todos,
        ));
      }
    } else {
      final List<String> data = _nullSplit(parts[0], 1).map/*<String>*/(UTF8.decode).toList();
      if (data.length < 3) {
        onError(new Exception('invalid data packet from Remy (insufficient data in notification packet): ${UTF8.decode(bytes)}'));
      } else {
        onNotification(new RemyNotification(
          data[1],
          new Set<String>.from(data[2].split(' ')),
          int.parse(
            data[0],
            onError: (String source) { onError(new Exception('unexpected "numeric" data from remy: $source')); }
          ),
        ));
      }
    }
  }

  static Iterable<List<int>> _nullSplit(List<int> bytes, int nullTarget) sync* {
    int start = 0;
    int index = 0;
    int nullCount = 0;
    while (index < bytes.length) {
      if (bytes[index] == 0x00) {
        nullCount += 1;
        if (nullCount == nullTarget) {
          yield bytes.sublist(start, index - (nullTarget - 1));
          nullCount = 0;
          start = index + 1;
        }
      } else {
        nullCount = 0;
      }
      index += 1;
    }
    yield bytes.sublist(start, index);
  }

  void pushButton(RemyButton button) {
    pushButtonById(button.id);
  }

  void pushButtonById(String name) {
    final String message = '$username\x00$password\x00$name\x00\x00\x00';
    if (_server != null) {
      _server.write(message);
    } else {
      _pendingMessages.add(message);
    }
  }

  void ping() {
    _server?.write('\x00\x00\x00');
  }

  void dispose() {
    _closed = true;
    _server?.destroy();
  }
}

class _RemyMessageParser extends StreamTransformerInstance<List<int>, List<int>> {
  _RemyMessageParser(this.nullTarget) {
    assert(nullTarget > 0);
  }

  static StreamTransformer<List<int>, List<int>> getTransformer(int nullTarget) {
    return new StreamTransformerBase<List<int>, List<int>>(
      () => new _RemyMessageParser(nullTarget)
    );
  }

  final int nullTarget;

  final List<int> _buffer = <int>[];
  int _index = 0;
  int _nullCount = 0;

  @override
  bool handleData(List<int> event, StreamSink<List<int>> output) {
    _buffer.addAll(event);
    while (_index < _buffer.length) {
      if (_buffer[_index] == 0x00) {
        _nullCount += 1;
        if (_nullCount == nullTarget) {
          output.add(_buffer.sublist(0, _index - (nullTarget - 1)));
          _buffer.removeRange(0, _index + 1);
          _index = -1;
          _nullCount = 0;
        }
      } else {
        _nullCount = 0;
      }
      _index += 1;
    }
    return false;
  }

  @override
  void handleDone(StreamSink<List<int>> output) {
  }
}