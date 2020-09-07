import 'dart:async';

import 'common.dart';

typedef void SinkCallback<T>(Sink<T> sink);
typedef void HandleData<T>(T data);

/// A broadcast stream that:
///
/// - immediately reports the most recent value when a new listener is added.
///
/// - never reports the same value twice (only reports changes).
///
/// - never raises an error.
abstract class WatchStream<T> extends Stream<T> implements Sink<T> {
  Set<_WatchStreamSubscription<T>> _subscriptions = new Set<_WatchStreamSubscription<T>>();

  void handleStart();
  void handleEnd();

  @override
  StreamSubscription<T> listen(
    void onData(T event), {
    Function onError,
    void onDone(),
    bool cancelOnError,
  }) {
    if (_subscriptions.isEmpty)
      handleStart();
    StreamSubscription<T> result = new _WatchStreamSubscription<T>(
      onData, onDone, this,
    );
    _subscriptions.add(result);
    return result;
  }

  T _value;

  // return value is whether this changed the status
  @override
  bool add(T value) {
    if (_value == value)
      return false;
    _value = value;
    // we take a local copy in case anyone tries to cancel themselves from inside their data handler
    // (as might happen e.g. with someone using Stream.first)
    final Set<_WatchStreamSubscription<T>> targets = new Set<_WatchStreamSubscription<T>>.from(_subscriptions);
    for (_WatchStreamSubscription<T> subscription in targets)
      subscription._sendValue();
    return true;
  }

  @override
  void close() {
    for (_WatchStreamSubscription<T> subscription in _subscriptions)
      subscription._dispose();
    if (_subscriptions.isNotEmpty)
      handleEnd();
    _subscriptions = null;
  }

  void _cancel(_WatchStreamSubscription<T> subscription) {
    assert(_subscriptions.contains(subscription));
    _subscriptions.remove(subscription);
    if (_subscriptions.isEmpty)
      handleEnd();
  }

  @override
  bool get isBroadcast => true;
}

class HandlerWatchStream<T> extends WatchStream<T> {
  HandlerWatchStream(this._onStart, this._onEnd);

  final SinkCallback<T> _onStart; // passes "this" as the sink argument
  
  final VoidCallback _onEnd;

  @override
  void handleStart() {
    if (_onStart != null)
      _onStart(this);
  }

  @override
  void handleEnd() {
    if (_onEnd != null)
      _onEnd();
  }
}

class AlwaysOnWatchStream<T> extends WatchStream<T> {
  @override
  void handleStart() { }

  @override
  void handleEnd() { }
}

class _WatchStreamSubscription<T> extends StreamSubscription<T> {
  _WatchStreamSubscription(this._handleData, this._handleDone, this._stream) {
    scheduleMicrotask(_sendValue);
  }

  final WatchStream<T> _stream;

  @override
  Future<Null> cancel() {
    _stream._cancel(this);
    return new Future<Null>.value(null);
  }

  HandleData<T> _handleData;
  @override
  void onData(HandleData<T> handleData) {
    _handleData = handleData;
  }
  
  @override
  void onError(Function handleError) {
    // errors not supported
  }
  
  VoidCallback _handleDone;
  @override
  void onDone(VoidCallback handleDone) {
    _handleDone = handleDone;
  }

  int _paused = 0;
  T _lastValue;
  bool _sentFirstValue = false;

  void _sendValue() {
    if (_paused == 0 && _handleData != null && (!_sentFirstValue || _stream._value != _lastValue)) {
      _lastValue = _stream._value;
      _sentFirstValue = true;
      _handleData(_stream._value);
    }
  }

  @override
  void pause([Future<dynamic> resumeSignal]) {
    _paused += 1;
    resumeSignal?.whenComplete(resume);
  }
  
  @override
  void resume() {
    if (_paused > 0) {
      _paused -= 1;
      _sendValue();
    }
  }

  @override
  bool get isPaused => _paused > 0;
  
  @override
  Future<E> asFuture<E>([E futureValue]) {
    Completer<E> completer = new Completer<E>();
    _handleDone = () {
      completer.complete(futureValue);
    };
    return completer.future;
  }

  void _dispose() {
    if (_handleDone != null)
      _handleDone();
  }
}
