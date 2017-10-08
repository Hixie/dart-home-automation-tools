import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'common.dart';
import 'temperature.dart';
import 'watch_stream.dart';

typedef void LittleBitsLogger(String deviceId, String message);
typedef String IdentifierCallback(String deviceId);

class CloudBitException implements Exception {
  const CloudBitException(this.message, this.cloudbit);
  final String message;
  final CloudBit cloudbit;
  @override
  String toString() => '$message (device ${cloudbit?.displayName})';
}

class CloudBitContractViolation extends CloudBitException {
  const CloudBitContractViolation(String message, [ CloudBit cloudbit ]) : super(message, cloudbit);
}

class CloudBitRateLimitException extends CloudBitException {
  const CloudBitRateLimitException([ CloudBit cloudbit ]) : super('cloudbit rate limit exceeded', cloudbit);
}

class CloudBitNotConnected extends CloudBitException {
  const CloudBitNotConnected(CloudBit cloudbit) : super('cloudbit not connected', cloudbit);
}

class CloudBitConnectionFailure extends CloudBitException {
  CloudBitConnectionFailure(CloudBit cloudbit, Exception exception) : exception = exception, super('cloudbit connection failure ($exception)', cloudbit);
  final Exception exception;
}

class LittleBitsCloud {
  LittleBitsCloud({
    @required this.authToken,
    this.onIdentify,
    this.onError,
    this.onLog,
  }) {
    _httpClient.userAgent = null;
    _log(null, 'initialized littlebits cloud manager');
  }

  final String authToken;

  final IdentifierCallback onIdentify;

  final ErrorHandler onError;

  final LittleBitsLogger onLog;

  final Map<String, CloudBit> _devices = <String, CloudBit>{};
  final HttpClient _httpClient = new HttpClient();

  /// How long to wait after exceeding the rate limit
  final Duration rateLimitDelay = const Duration(seconds: 20);

  /// How long to wait after finding out that the cloudbit is not connected.
  final Duration noConnectionDelay = const Duration(seconds: 10);

  /// How long to wait after being disconnected from the cloudbit cloud
  final Duration reconnectDelay = const Duration(seconds: 2);

  CloudBit getDevice(String deviceId) {
    return _devices.putIfAbsent(deviceId, () {
      final String name = onIdentify(deviceId);
      _log(deviceId, 'adding "$name" to cloudbit library ($deviceId)', level: LogLevel.verbose);
      return new CloudBit._(this, deviceId, name);
    });
  }

  Stream<CloudBit> listDevices() async* {
    _log(null, 'obtaining device list...');
    dynamic data;
    do {
      final HttpClientRequest request = await _httpClient.getUrl(Uri.parse('https://api-http.littlebitscloud.cc/v2/devices'));
      request.headers.set(HttpHeaders.AUTHORIZATION, authToken);
      final HttpClientResponse response = await request.close();
      switch (response.statusCode) {
        case 429:
          await _reportError(exception: const CloudBitRateLimitException(), duration: rateLimitDelay);
          await response.drain();
          continue;
        case 200:
          break;
        default:
          await response.drain();
          throw new CloudBitContractViolation('unexpected error from littlebits cloud (${response.statusCode} ${response.reasonPhrase})');
      }
      final String rawData = await response.transform(UTF8.decoder).single;
      await response.drain();
      try {
        data = JSON.decode(rawData);
      } on FormatException {
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not JSON: "$rawData")');
      }
      if (data is! List)
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not a list: "$data")');
      break;
    } while (true);
    _log(null, 'device list obtained with ${data.length} device${ data.length == 1 ? "" : "s"}');
    for (dynamic device in data) {
      if (device is! Map)
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (not a list of objects)');
      if (!device.containsKey('id'))
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (device object does not have "id" field)');
      final dynamic id = device['id'];
      if (id is! String)
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (unexpected id format)');
      yield getDevice(id);
    }
  }

  Future<Null> _reportError({
    @required dynamic exception,
    Duration duration,
    bool connected,
    void continuation(),
  }) {
    List<Future<Null>> prerequisites = <Future<Null>>[];
    if (duration != null)
      prerequisites.add(new Future<Null>.delayed(duration));
    if (onError != null) {
      if (connected || exception is! CloudBitNotConnected) {
        Future<Null> errorFuture = onError(exception);
        if (errorFuture != null)
          prerequisites.add(errorFuture);
      }
    }
    return Future.wait(prerequisites).then((List<Null> value) {
      if (continuation != null)
        continuation();
    });
  }

  void dispose() {
    _httpClient.close(force: true);
    for (CloudBit cloudbit in _devices.values)
      cloudbit.dispose();
  }

  void _log(String deviceId, String message, { LogLevel level: LogLevel.info }) {
    if (onLog != null && level.index <= LogLevel.info.index)
      onLog(deviceId, message);
  }
}

class CloudBit {
  CloudBit._(this.cloud, this.deviceId, this.displayName) {
    _valueStream = new HandlerWatchStream<int>(_start, _end);
  }

  final LittleBitsCloud cloud;
  final String deviceId;
  final String displayName;

  WatchStream<int> _valueStream;

  Future<String> get label async {
    do {
      final HttpClientRequest request = await cloud._httpClient.getUrl(Uri.parse('https://api-http.littlebitscloud.cc/v2/devices/$deviceId'));
      request.headers.set(HttpHeaders.AUTHORIZATION, cloud.authToken);
      final HttpClientResponse response = await request.close();
      switch (response.statusCode) {
        case 429:
          await cloud._reportError(
            exception: new CloudBitRateLimitException(this),
            duration: cloud.rateLimitDelay,
          );
          await response.drain();
          continue;
        case 200:
          break;
        default:
          await response.drain();
          throw new CloudBitContractViolation('unexpected error from littlebits cloud (${response.statusCode} ${response.reasonPhrase})', this);
      }
      final String rawData = await response.transform(UTF8.decoder).single;
      await response.drain();
      dynamic device;
      try {
        device = JSON.decode(rawData);
      } on FormatException {
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not JSON: "$rawData")', this);
      }
      if (device is! Map)
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not a map: "$device")', this);
      if (!device.containsKey('label'))
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (device object does not have "label" field)', this);
      final dynamic label = device['label'];
      if (label is! String)
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (unexpected label format)', this);
      return label;
    } while (true);
  }

  static const Duration resendDelay = const Duration(seconds: 1);

  bool _sending = false;
  int _pendingSendValue;
  Future<Null> _sendValue(int value, Duration duration, { bool silent: false }) async {
    assert(value >= 0);
    assert(value <= 99);
    if (!silent)
      cloud._log(deviceId, '$displayName: sending $value${_sending ? " (previous send already in progress)" : ""}');
    _pendingSendValue = value;
    if (_sending)
      return;
    _sending = true;
    do {
      HttpClientRequest request;
      try {
        request = await cloud._httpClient.postUrl(Uri.parse('https://api-http.littlebitscloud.cc/v2/devices/$deviceId/output'));
      } catch (exception) {
        await cloud._reportError(
          exception: new CloudBitConnectionFailure(this, exception),
          connected: _connected,
          duration: cloud.noConnectionDelay,
        );
        break;
      }
      request.headers.set(HttpHeaders.AUTHORIZATION, cloud.authToken);
      request.headers.contentType = new ContentType('application', 'json');
      request.headers.contentLength = -1;
      int _sentValue = _pendingSendValue;
      request.write(JSON.encode(<String, int>{
        'percent': _pendingSendValue,
        'duration_ms': duration == null ? -1 : duration.inMilliseconds,
      }));
      final HttpClientResponse response = await request.close();
      cloud._log(deviceId, '$displayName: when sending $_sentValue, got ${response?.statusCode}', level: LogLevel.verbose);
      switch (response.statusCode) {
        case 429:
          await cloud._reportError(
            exception: new CloudBitRateLimitException(this),
            duration: cloud.rateLimitDelay,
          );
          await response.drain();
          break;
        case 404:
          await cloud._reportError(
            exception: new CloudBitNotConnected(this),
            connected: _connected,
            duration: cloud.noConnectionDelay,
          );
          await response.drain();
          break;
        case 200:
          await response.drain();
          if (!silent)
            cloud._log(deviceId, '$displayName: sent $_pendingSendValue successfully!', level: LogLevel.verbose);
          if (_sentValue == _pendingSendValue)
            _pendingSendValue = null;
          await new Future<Null>.delayed(resendDelay);
          break;
        default:
          await cloud._reportError(
            exception: new CloudBitContractViolation('unexpected error from littlebits cloud (${response.statusCode} ${response.reasonPhrase})', this),
            duration: cloud.rateLimitDelay,
          );
          await response.drain();
      }
    } while (_pendingSendValue != null);
    _sending = false;
  }

  /// Set the cloudbit output value. The range is 0..1023.
  ///
  /// Setting the value (via this method or the others) is rate-limited
  /// to one per second. It is safe to call this at a higher rate; the
  /// extraneous calls are just silently dropped.
  void setValue(int value, { Duration duration, bool silent: false }) {
    assert(value >= 0);
    assert(value <= 1023);
    _sendValue(((value / 1023.0) * 99.0).round(), duration, silent: silent);
  }

  /// Set the cloudbit output value such that it will display `value`
  /// on an o21 number bit in "value" mode. Range is 0..99.
  ///
  /// See [setValue].
  void setNumberValue(int value, { Duration duration, bool silent: false }) {
    assert(value >= 0);
    assert(value <= 99);
    _sendValue(value, duration, silent: silent);
  }

  /// Set the cloudbit output value such that it will display `value`
  /// on an o21 number bit in "volts" mode. Range is 0.0..5.0.
  ///
  /// See [setValue].
  void setNumberVolts(double value, { Duration duration, bool silent: false }) {
    assert(value >= 0.0);
    assert(value <= 5.0);
    _sendValue((99.0 * value / 5.0).round(), duration, silent: silent);
  }

  /// Set the cloudbit output value such that it will display `value`
  /// on an o21 number bit in "volts" mode. Range is 0.0..5.0.
  ///
  /// See [setValue].
  void setBooleanValue(bool value, { Duration duration, bool silent: false }) {
    _sendValue(value ? 99 : 0, duration, silent: silent);
  }

  StreamSubscription<dynamic> _events;
  bool _active = false;

  static const Duration reconnectDuration = const Duration(seconds: 5);
  static const Duration idleTimeout = const Duration(minutes: 5);

  Stream<int> get values => new StreamView<int>(_valueStream);

  Future<Null> _start(Sink<int> sink) async {
    _active = true;
    while (_active) {
      cloud._log(deviceId, '$displayName: connecting...', level: LogLevel.verbose);
      await _connect(sink);
      cloud._log(deviceId, '$displayName: connection lost. (${_active ? "still active" : "now inactive anyway" })', level: LogLevel.verbose);
    }
    cloud._log(deviceId, '$displayName: disconnected, not active', level: LogLevel.verbose);
  }

  Future<Null> _connect(Sink<int> sink) async {
    cloud._log(deviceId, '$displayName: attempting connection...', level: LogLevel.verbose);
    HttpClientResponse response;
    try {
      final HttpClientRequest request = await cloud._httpClient.getUrl(Uri.parse('https://api-http.littlebitscloud.cc/v2/devices/$deviceId/input'));
      request.headers.set(HttpHeaders.AUTHORIZATION, cloud.authToken);
      response = await request.close();
    } catch (error) {
      cloud._log(deviceId, 'unexpected error: $error');
      return _error(error);
    }
    assert(response != null);
    switch (response.statusCode) {
      case 429:
        cloud._log(deviceId, '$displayName: 429 rate-limit; delaying ${cloud.rateLimitDelay}', level: LogLevel.verbose);
        await response.drain();
        return _error(new CloudBitRateLimitException(this), cloud.rateLimitDelay);
      case 404:
        cloud._log(deviceId, '$displayName: 404 not-connected; delaying ${cloud.noConnectionDelay}', level: LogLevel.verbose);
        await response.drain();
        return _error(new CloudBitNotConnected(this), cloud.noConnectionDelay);
      case 200:
        cloud._log(deviceId, '$displayName: connected', level: LogLevel.verbose);
        break;
      default:
        cloud._log(deviceId, '$displayName: contract violation: $response');
        await response.drain();
        return _error(new CloudBitContractViolation('unexpected error from littlebits cloud (${response.statusCode} ${response.reasonPhrase})', this));
    }
    Completer<Null> completer = new Completer<Null>();
    _events = response
      .transform(UTF8.decoder)
      .transform(const LineSplitter())
      .transform(new StreamTransformer<String, dynamic>.fromHandlers(
        handleData: (String data, EventSink<dynamic> sink) {
          if (data.isEmpty)
            return;
          if (data.startsWith('data:')) {
            try {
              sink.add(JSON.decode(data.substring(5))); // 5 is the length of the string 'data:'
              return;
            } on FormatException {
              // absorb exception; we'll report it below
            }
          }
          completer.complete(_error(new CloudBitContractViolation('unexpected data from CloudBit stream: "$data"', this)));
        },
      ))
      .timeout(idleTimeout)
      .listen(
        (dynamic event) {
          if (event is! Map) {
            completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud (not a map: "$event")', this)));
            return;
          }
          if (!event.containsKey('type')) {
            completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud (event does not contain "type" value: "$event")', this)));
            return;
          }
          final dynamic type = event['type'];
          if (type is! String) {
            completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud ("type" value is not String: "$event")', this)));
            return;
          }
          if (type == 'input') {
            if (!event.containsKey('absolute')) {
              completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud (input event does not contain "absolute" value: "$event")', this)));
              return;
            }
            final dynamic value = event['absolute'];
            if (value is! int) {
              completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud ("absolute" value is not numeric: "$event")', this)));
              return;
            }
            _emit(value);
          } else if (type == 'connection_change') {
            if (!event.containsKey('state')) {
              completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud (connection_change event does not contain "state" value: "$event")', this)));
              return;
            }
            final dynamic state = event['state'];
            if (state is! int) {
              completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud ("state" value is not numeric: "$event")', this)));
              return;
            }
            switch (state) {
              case 0: // disconnected
              case 1: // disconnecting
                final bool wasConnected = _connected;
                _emit(null);
                // We're still connected to the cloud, so only report the error, don't
                // call _error (which will disconnect and reconnect).
                cloud._reportError(exception: new CloudBitNotConnected(this), connected: wasConnected);
                assert(_connected == false);
                break;
              case 2: // connected
                break;
              default:
                completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud ("state" value out of range: "$event")', this)));
                return;
            }
          } else {
            completer.complete(_error(new CloudBitContractViolation('unexpected data received from littlebits cloud (unknown "type" value: "$event")', this)));
            return;
          }
        },
        onError: (dynamic exception, StackTrace stack) {
          cloud._log(deviceId, '$displayName: got exception from events stream: $exception');
          completer.complete(_error(exception));
        },
        onDone: () {
          completer.complete(_error(new CloudBitContractViolation('unexpectedly disconnected from littlebits cloud', this)));
        },
      );
    return completer.future;
  }

  Future<Null> _error(dynamic exception, [ Duration duration = reconnectDuration ]) async {
    // fatal error on socket, disconnect and try again after given duration
    cloud._log(deviceId, '$displayName: reporting error "$exception" (${_active ? "still active" : "now inactive"})', level: LogLevel.verbose);
    assert(duration != null);
    final bool wasConnected = _connected;
    _emit(null);
    assert(!_connected);
    _events?.cancel();
    _events = null;
    final Completer<Null> completer = new Completer<Null>();
    cloud._reportError(
      exception: exception,
      duration: duration,
      connected: wasConnected,
      continuation: () {
        cloud._log(deviceId, '$displayName: post-error continuation (${_active ? "still active" : "now inactive"})', level: LogLevel.verbose);
        completer.complete();
      },
    );
    assert(!_connected);
    return completer.future;
  }

  bool _connected = false;

  void _emit(int value) {
    if (_connected != (value != null))
      cloud._log(deviceId, '$displayName: ${value == null ? "disconnected" : "connected"}', level: LogLevel.verbose);
    _connected = value != null;
    _valueStream.add(value);
  }

  void _end() {
    cloud._log(deviceId, '$displayName: disconnecting.', level: LogLevel.verbose);
    _active = false;
    _events?.cancel();
    _events = null;
  }

  void dispose() {
    cloud._log(deviceId, '$displayName: disposing...', level: LogLevel.verbose);
    _end();
    _valueStream.close();
  }

  @override
  String toString() => '$runtimeType($displayName, $deviceId)';
}

class BitDemultiplexer {
  BitDemultiplexer(this.input, this.bitCount) {
    assert(bitCount >= 2);
    assert(bitCount <= 4);
  }

  final Stream<int> input;
  final int bitCount;

  final Map<int, WatchStream<bool>> _outputs = <int, WatchStream<bool>>{};
  final Set<int> _activeBits = new Set<int>();

  /// Obtain a stream for the given bit, in the range 1..[bitCount].
  ///
  /// The bit with number [bitCount] is the high-order bit, 40 in the
  /// cloudbit 0..99 range. Lower bits are 20, 10, and 5.
  ///
  /// The stream that you get here is always sent either true or false,
  /// you don't have to check for null.
  Stream<bool> operator [](int bit) {
    assert(bit >= 1);
    assert(bit <= bitCount);
    return new StreamView<bool>(_outputs.putIfAbsent(bit, () => _setup(bit)));
  }

  WatchStream<bool> _setup(int bit) {
    final WatchStream<bool> controller = new HandlerWatchStream<bool>((Sink<bool> sink) => _start(bit), () => _end(bit));
    return controller;
  }

  StreamSubscription<int> _subscription;

  void _start(int bit) {
    if (_activeBits.isEmpty) {
      assert(_subscription == null);
      _subscription = input.listen(_handleInput);
    }
    _activeBits.add(bit);
  }

  void _end(int bit) {
    _activeBits.remove(bit);
    if (_activeBits.isEmpty) {
      assert(_subscription != null);
      _subscription.cancel();
    }
  }

  void _handleInput(int value) {
    if (value != null) {
      final int bitfield = valueToBitField(value, bitCount);
      for (int bit = 1; bit <= bitCount; bit += 1)
        _dispatchBit(bit, bitfield & (1 << (bit - 1)) != 0);
    }
  }

  static int valueToBitField(int value, int bitCount) {
    assert(value != null);
    assert(value >= 0);
    assert(value <= 1023);
    final double scaledValue = (value / 1023.0) * 99.0; // convert to the range seen by the o21 number bit for ease of debugging
    final double floatingBitfield = scaledValue / (40.0 / (1 << (bitCount - 1)));
    final int bitfield = floatingBitfield.round().clamp(0, (1 << bitCount) - 1);
    return bitfield;
  }

  void _dispatchBit(int bit, bool value) {
    if (_activeBits.contains(bit))
      _outputs[bit].add(value);
  }

  void dispose() {
    for (WatchStream<bool> bit in _outputs.values)
      bit.close();
  }
}

// All else being equal, using F is better because the precision is greater
class TemperatureSensor extends Temperature {
  const TemperatureSensor.F(this._value) : _valueIsF = true;
  const TemperatureSensor.C(this._value) : _valueIsF = false;
  final int _value; // 0..1024
  final bool _valueIsF;
  @override
  double get fahrenheit => _valueIsF ? 100.0 * _value / 1023.0 : celsius * 9.0 / 5.0 + 32.0;
  @override
  double get celsius => _valueIsF ? (fahrenheit - 32.0) * 5.0 / 9.0 : 100.0 * _value / 1023.0;
}

StreamHandler<int> getAverageValueLogger({
  @required Logger log,
  @required String name,
  double slop: 1023.0 * 0.01, // 1% of total range
  double reportingThreshold: 1023.0 * 0.001, // 0.1% of total range
}) {
  bool connected;
  double average;
  int countedValues;
  return (int value) {
    final bool lastConnected = connected;
    connected = value != null;
    if (connected != lastConnected)
      log('${connected ? 'connected to' : 'disconnected from'} $name cloudbit');
    if (value == null)
      return;
    if (average == null || (average - value.toDouble()).abs() > slop) {
      log('cloudbit raw value $value, far outside previous average (${average?.toStringAsFixed(1)})');
      average = value.toDouble();
      countedValues = 1;
    } else {
      final double oldAverage = average;
      average = (average * countedValues + value) / (countedValues.toDouble() + 1.0);
      countedValues += 1;
      if ((oldAverage - average).abs() > reportingThreshold)
        log('cloudbit raw value $value, new average is ${average.toStringAsFixed(1)}');
    }
  };
}
