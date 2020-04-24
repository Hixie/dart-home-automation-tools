import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../watch_stream.dart';

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
    int port: 12649,
    @required this.username,
    @required this.password,
    this.onLog,
    this.onNotification,
    this.onUiUpdate,
    this.onConnected,
    this.onDisconnected,
  }) {
    assert(port != null);
    _connect(host, port);
  }

  final String username;
  final String password;
  final LogCallback onLog;
  final NotificationHandler onNotification;
  final UiUpdateHandler onUiUpdate;
  final VoidCallback onConnected;
  final VoidCallback onDisconnected;

  Socket _server;
  Completer<Null> _closed = new Completer<Null>();
  Timer _keepAlive;

  final List<String> _pendingMessages = <String>[];

  Future<Null> _connect(InternetAddress host, int port) async {
    do {
      try {
        if (host == null) {
          final List<InternetAddress> hosts = await InternetAddress.lookup('remy.rooves.house');
          if (hosts.isEmpty)
            throw new Exception('Cannot lookup Remy\'s internet address: no results');
          host = hosts.first;
        }
        _server = await SecureSocket.connect(host, port);
        _server.encoding = utf8;
        if (onUiUpdate != null) {
          _server.write('enable-ui\x00\x00\x00');
          await _server.flush().catchError(
            (dynamic error, StackTrace stack) => throw new Exception('could not connect to Remy'),
            test: (dynamic error) => error is StateError,
          );
        }
        if (onConnected != null)
          onConnected();
        _keepAlive = new Timer.periodic(const Duration(seconds: 60), (Timer t) => ping());
        await Future.any(<Future<Null>>[
          _listen(_server.transform(_RemyMessageParser.getTransformer(3))),
          _writeLoop(),
          _closed.future,
        ]);
      } catch (error) {
        if (onLog != null)
          onLog('error listening to Remy: $error');
      }
      _disconnect();
      if (!_closed.isCompleted)
        await new Future<Null>.delayed(const Duration(seconds: 1));
    } while (!_closed.isCompleted);
  }

  void _disconnect() {
    _keepAlive?.cancel();
    _keepAlive = null;
    if (_signalPendingMessage != null && !_signalPendingMessage.isCompleted)
      _signalPendingMessage.complete(false);
    _server?.destroy();
    _server = null;
    if (onDisconnected != null)
      onDisconnected();
  }

  Future<Null> _listen(Stream<List<int>> messages) async {
    await for (List<int> bytes in messages)
      _handleMessage(bytes);
    return null;
  }

  /// The last UI description received.
  ///
  /// This is initially null.
  ///
  /// This will remain null if [onUiUpdate] is null.
  RemyUi get currentState => _currentState;
  RemyUi _currentState;

  void _handleMessage(List<int> bytes) {
    if (bytes.length == 0) {
      // pong
      return;
    }
    List<List<int>> parts = _nullSplit(bytes, 2).toList();
    if (utf8.decode(parts[0]) == 'update') {
      if (onUiUpdate != null) {
        final Map<String, RemyButton> buttons = <String, RemyButton>{};
        final Set<RemyMessage> messages = new Set<RemyMessage>();
        final Set<RemyToDo> todos = new Set<RemyToDo>();
        for (List<int> entry in parts.skip(1)) {
          final List<String> data = _nullSplit(entry, 1).map<String>(utf8.decode).toList();
          if (data.isEmpty) {
            if (onLog != null)
              onLog('invalid data packet from Remy (has empty entry in UI update): ${utf8.decode(bytes)}');
          } else if (data[0] == 'button') {
            if (data.length < 4) {
              if (onLog != null)
                onLog('invalid data packet from Remy (insufficient data in button packet): ${utf8.decode(bytes)}');
            } else if (buttons.containsKey(data[1])) {
              if (onLog != null)
                onLog('received duplicate button ID');
            } else {
              buttons[data[1]] = new RemyButton(data[1], new Set<String>.from(data[2].split(' ')), data[3]);
            }
          } else if (data[0] == 'message') {
            if (data.length < 4) {
              if (onLog != null)
                onLog('invalid data packet from Remy (insufficient data in message packet): ${utf8.decode(bytes)}');
            } else {
              messages.add(new RemyMessage(
                data[1],
                new Set<String>.from(data[2].split(' ')),
                _parseEscalationLevel(data[3]),
                data.sublist(4).map<RemyButton>((String id) {
                  if (buttons.containsKey(id))
                    return buttons[id];
                  if (onLog != null)
                    onLog('unknown button ID in message "${data[1]}" from Remy: $id');
                  return null;
                }).where((RemyButton button) => button != null).toList(),
              ));
            }
          } else if (data[0] == 'todo') {
            if (data.length < 5) {
              if (onLog != null)
                onLog('invalid data packet from Remy (insufficient data in todo packet): ${utf8.decode(bytes)}');
            } else {
              todos.add(new RemyToDo(
                data[1],
                data[2],
                new Set<String>.from(data[3].split(' ')),
                _parseEscalationLevel(data[4]),
              ));
            }
          } else {
            if (onLog != null)
              onLog('unexpected data from Remy: ${utf8.decode(bytes)}');
          }
        }
        _currentState = new RemyUi(
          new Set<RemyButton>.from(buttons.values),
          messages,
          todos,
        );
        onUiUpdate(currentState);
      }
    } else {
      final List<String> data = _nullSplit(parts[0], 1).map<String>(utf8.decode).toList();
      if (data.length < 3) {
        if (onLog != null)
          onLog('invalid data packet from Remy (insufficient data in notification packet): ${utf8.decode(bytes)}');
      } else {
        if (onNotification != null) {
          onNotification(new RemyNotification(
            data[1],
            new Set<String>.from(data[2].split(' ')),
            _parseEscalationLevel(data[0]),
          ));
        }
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

  int _parseEscalationLevel(String value) {
    int escalationLevel = int.tryParse(value);
    if (escalationLevel == null) {
      if (onLog != null)
        onLog('unexpected "numeric" data from Remy: $value');
      escalationLevel = 0;
    }
    return escalationLevel;
  }

  void pushButton(RemyButton button) {
    pushButtonById(button.id);
  }

  void pushButtonById(String name) {
    _send('$username\x00$password\x00$name\x00\x00\x00');
  }

  void ping() {
    if (_pendingMessages.isEmpty && _server != null)
      _send('\x00\x00\x00');
  }

  Completer<bool> _signalPendingMessage;

  void _send(String message) {
    _pendingMessages.add(message);
    if (_signalPendingMessage != null && !_signalPendingMessage.isCompleted)
      _signalPendingMessage.complete(true);
  }

  Future<Null> _writeLoop() async {
    try {
      do {
        // TODO(ianh): Move pending messages into a list that waits for confirmation
        // and brings them back into the pending list if not confirmed in a short time
        while (_pendingMessages.isNotEmpty)
          _server.write(_pendingMessages.removeAt(0));
        _signalPendingMessage = new Completer<bool>();
        await _server.flush();
      } while (await _signalPendingMessage.future);
    } finally {
      _signalPendingMessage = null;
    }
  }

  void dispose() {
    _closed.complete();
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

class RemyMultiplexer {
  RemyMultiplexer(String username, String password, { this.onLog }) {
    _remy = new Remy(
      username: username,
      password: password,
      onUiUpdate: _handleUiUpdate,
      onNotification: _handleNotification,
      onLog: _log,
      onConnected: () {
        _log('connected');
      },
      onDisconnected: () {
        _log('disconnected');
      },
    );
  }

  final LogCallback onLog;

  Remy _remy;

  final Map<String, WatchStream<bool>> _notificationStatuses = <String, WatchStream<bool>>{};
  final Map<String, StreamController<String>> _notificationsWithArguments = <String, StreamController<String>>{};
  final StreamController<RemyNotification> _notifications = new StreamController<RemyNotification>.broadcast();

  Future<Null> get ready => _ready.future;
  final Completer<Null> _ready = new Completer<Null>();

  Stream<RemyNotification> get notifications => _notifications.stream;

  RemyUi get currentState => _remy.currentState;

  Set<String> _lastLabels = new Set<String>();

  void _handleUiUpdate(RemyUi ui) {
    if (!_ready.isCompleted)
      _ready.complete();
    Set<String> labels = new HashSet<String>.from(ui.messages.map((RemyNotification notification) => notification.label));
    for (String label in _notificationStatuses.keys)
      _notificationStatuses[label].add(labels.contains(label));
    Set<String> labelPrefixes = new HashSet<String>.from(_notificationsWithArguments.keys);
    for (String label in labels) {
      if (_lastLabels.contains(label))
        continue; // we only report new values
      int spaceIndex = label.indexOf(' ');
      if (spaceIndex <= 0)
        continue;
      String prefix = label.substring(0, spaceIndex);
      if (labelPrefixes.contains(prefix))
        _notificationsWithArguments[prefix].add(label.substring(spaceIndex + 1));
    }
    _lastLabels = labels;
  }

  void _handleNotification(RemyNotification notification) {
    _notifications.add(notification);
  }

  /// Returns the [WatchStream<bool>] for the on/off state of this particular notification.
  ///
  /// The first value may be null, meaning that the current state is unknown.
  WatchStream<bool> getStreamForNotification(String label) {
    return _notificationStatuses.putIfAbsent(label, () {
      WatchStream<bool> result = new AlwaysOnWatchStream<bool>();
      if (_remy.currentState != null)
        result.add(_remy.currentState.messages.any((RemyNotification notification) => notification.label == label));
      return result;
    });
  }

  /// Returns the [Stream<String>] for the value of a notification of the form "label argument".
  ///
  /// Each time the notification fires, the argument is sent to the stream.
  Stream<String> getStreamForNotificationWithArgument(String label) {
    return _notificationsWithArguments.putIfAbsent(label, () {
      return new StreamController<String>.broadcast(
        onCancel: () => _notificationsWithArguments.remove(label),
      );
    }).stream;
  }

  bool hasNotification(String label) {
    assert(_remy.currentState != null);
    return _remy.currentState.messages.any((RemyNotification notification) => notification.label == label);
  }

  void pushButton(RemyButton button) {
    _log('pushing button ${button.id}');
    _remy.pushButton(button);
  }

  void pushButtonById(String name) {
    _log('pushing button $name');
    _remy.pushButtonById(name);
  }

  void _log(String message) {
    if (onLog != null)
      onLog(message);
  }
}
