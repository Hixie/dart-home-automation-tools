import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../watch_stream.dart';
import 'cloudbit.dart';

class CloudBitContractViolation extends CloudBitException {
  const CloudBitContractViolation(String message, [ CloudBit cloudbit ]) : super(message, cloudbit);
}

class CloudBitRateLimitException extends CloudBitException {
  const CloudBitRateLimitException([ CloudBit cloudbit ]) : super('cloudbit rate limit exceeded', cloudbit);
}

class CloudBitNotConnected extends CloudBitException {
  const CloudBitNotConnected(CloudBit cloudbit, String message) : super('cloudbit not connected ($message)', cloudbit);
}

class CloudBitConnectionFailure extends CloudBitException {
  CloudBitConnectionFailure(CloudBit cloudbit, Exception exception) : exception = exception, super('cloudbit connection failure ($exception)', cloudbit);
  final Exception exception;
}

typedef String IdentifierCallback(String deviceId);

class LittleBitsCloud extends CloudBitProvider {
  LittleBitsCloud({
    @required this.authToken,
    this.onIdentify,
    ErrorHandler onError,
    DeviceLogCallback onLog,
  }) : super(onLog: onLog, onError: onError) {
    _httpClient.userAgent = null;
    log(null, 'initialized littlebits remote cloud manager');
  }

  final String authToken;

  final IdentifierCallback onIdentify;

  final Map<String, _CloudBit> _devices = <String, _CloudBit>{};
  final HttpClient _httpClient = new HttpClient();

  /// How long to wait after exceeding the rate limit
  final Duration rateLimitDelay = const Duration(seconds: 20);

  /// How long to wait after finding out that the cloudbit is not connected.
  final Duration noConnectionDelay = const Duration(seconds: 10);

  /// How long to wait after being disconnected from the cloudbit cloud
  final Duration reconnectDelay = const Duration(seconds: 2);

  @override
  Future<CloudBit> getDevice(String deviceId) {
    final _CloudBit cloudbit = _devices.putIfAbsent(deviceId, () {
      final String name = onIdentify(deviceId);
      log(deviceId, 'adding "$name" to cloudbit library ($deviceId)', level: LogLevel.verbose);
      return new _CloudBit._(this, deviceId, name);
    });
    return new Future<CloudBit>.value(cloudbit);
  }

  Future<HttpClientRequest> openRequest(String method, String url) async {
    log(null, '$method $url', level: LogLevel.verbose);
    final HttpClientRequest request = await _httpClient.openUrl(method, Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    return request;
  }

  Stream<CloudBit> listDevices() async* {
    log(null, 'obtaining device list...');
    dynamic data;
    do {
      final HttpClientRequest request = await openRequest('get', 'https://api-http.littlebitscloud.cc/v2/devices');
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
      final String rawData = await response.transform(utf8.decoder).single;
      await response.drain();
      try {
        data = json.decode(rawData);
      } on FormatException {
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not JSON: "$rawData")');
      }
      if (data is! List)
        throw new CloudBitContractViolation('unexpected data received from littlebits cloud (not a list: "$data")');
      break;
    } while (true);
    log(null, 'device list obtained with ${data.length} device${ data.length == 1 ? "" : "s"}');
    for (dynamic device in data) {
      if (device is! Map)
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (not a list of objects)');
      if (!device.containsKey('id'))
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (device object does not have "id" field)');
      final dynamic id = device['id'];
      if (id is! String)
        throw const CloudBitContractViolation('unexpected data received from littlebits cloud (unexpected id format)');
      yield await getDevice(id);
    }
  }

  Future<Null> _reportError({
    @required dynamic exception,
    Duration duration,
    bool connected: false,
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

  @override
  void dispose() {
    _httpClient.close(force: true);
    for (CloudBit cloudbit in _devices.values)
      cloudbit.dispose();
  }
}

class _CloudBit extends CloudBit {
  _CloudBit._(this.cloud, this.deviceId, this.displayName) {
    _valueStream = new HandlerWatchStream<int>(_start, _end);
  }

  final LittleBitsCloud cloud;

  @override
  final String deviceId;

  @override
  final String displayName;

  WatchStream<int> _valueStream;

  Future<String> get label async {
    do {
      final HttpClientRequest request = await cloud.openRequest('get', 'https://api-http.littlebitscloud.cc/v2/devices/$deviceId');
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
      final String rawData = await response.transform(utf8.decoder).single;
      await response.drain();
      dynamic device;
      try {
        device = json.decode(rawData);
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
  Future<Null> _sendValue(int value, { Duration duration, bool silent: false }) async {
    assert(value >= 0);
    assert(value <= 99);
    if (!silent)
      cloud.log(deviceId, '$displayName: sending $value${_sending ? " (previous send already in progress)" : ""}');
    _pendingSendValue = value;
    if (_sending)
      return;
    _sending = true;
    do {
      HttpClientRequest request;
      try {
        request = await cloud.openRequest('post', 'https://api-http.littlebitscloud.cc/v2/devices/$deviceId/output');
      } catch (exception, stack) {
        cloud.log(deviceId, '$exception\n$stack', level: LogLevel.verbose);
        await cloud._reportError(
          exception: new CloudBitConnectionFailure(this, exception),
          connected: _connected,
          duration: cloud.noConnectionDelay,
        );
        break;
      }
      request.headers.contentType = new ContentType('application', 'json');
      request.headers.contentLength = -1;
      int _sentValue = _pendingSendValue;
      request.write(json.encode(<String, int>{
        'percent': _pendingSendValue,
        'duration_ms': duration == null ? -1 : duration.inMilliseconds,
      }));
      HttpClientResponse response;
      try {
        response = await request.close();
      } catch (exception, stack) {
        cloud.log(deviceId, '$exception\n$stack', level: LogLevel.verbose);
        await cloud._reportError(
          exception: new CloudBitConnectionFailure(this, exception),
          connected: _connected,
          duration: cloud.noConnectionDelay,
        );
        break;
      }
      cloud.log(deviceId, '$displayName: when sending $_sentValue, got ${response.statusCode}', level: LogLevel.verbose);
      switch (response.statusCode) {
        case 429:
          await cloud._reportError(
            exception: new CloudBitRateLimitException(this),
            duration: cloud.rateLimitDelay,
          );
          await response.drain();
          break;
        case 404:
          final String message = await response.transform(utf8.decoder).join();
          await cloud._reportError(
            exception: new CloudBitNotConnected(this, 'trying to send $_pendingSendValue: $message'),
            connected: _connected,
            duration: cloud.noConnectionDelay,
          );
          // no need to drain since we read the message above
          break;
        case 200:
          await response.drain();
          if (!silent)
            cloud.log(deviceId, '$displayName: sent $_pendingSendValue successfully!', level: LogLevel.verbose);
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

  @override
  void set16bitValue(int value, { bool silent: false }) {
    assert(value >= 0x0000);
    assert(value <= 0xFFFF);
    _sendValue(((value / 65535.0) * 99.0).round(), silent: silent);
  }

  @override
  void setValue(int value, { Duration duration, bool silent: false }) {
    assert(value >= 0);
    assert(value <= 1023);
    _sendValue(((value / 1023.0) * 99.0).round(), duration: duration, silent: silent);
  }

  @override
  void setNumberValue(int value, { Duration duration, bool silent: false }) {
    assert(value >= 0);
    assert(value <= 99);
    _sendValue(value, duration: duration, silent: silent);
  }

  @override
  void setNumberVolts(double value, { Duration duration, bool silent: false }) {
    assert(value >= 0.0);
    assert(value <= 5.0);
    _sendValue((99.0 * value / 5.0).round(), duration: duration, silent: silent);
  }

  @override
  void setBooleanValue(bool value, { Duration duration, bool silent: false }) {
    _sendValue(value ? 99 : 0, duration: duration, silent: silent);
  }

  @override
  void setLedColor(LedColor color) {
    // TODO(ianh): See the script on https://littlebits.com/projects/colorful-cloudbit
    // which does this:
    // curl -i -XPOST -H "Authorization: Bearer (access token goes here)" https://api-http.littlebitscloud.cc/v3/devices/(device id goes here)/light -d color=purple -d duration_ms=300000
  }

  StreamSubscription<dynamic> _events;
  bool _active = false;

  static const Duration reconnectDuration = const Duration(seconds: 5);
  static const Duration idleTimeout = const Duration(minutes: 5);

  @override
  Stream<int> get values => new StreamView<int>(_valueStream);

  @override
  Stream<bool> get button => new Stream<bool>.empty();

  Future<Null> _start(Sink<int> sink) async {
    _active = true;
    while (_active) {
      cloud.log(deviceId, '$displayName: connecting...', level: LogLevel.verbose);
      try {
        await _connect(sink);
      } catch (error, stack) {
        cloud.log(deviceId, '$displayName: unexpected exception $error');
        cloud.log(deviceId, stack.toString(), level: LogLevel.verbose);
      }
      cloud.log(deviceId, '$displayName: connection lost. (${_active ? "still active" : "now inactive anyway" })', level: LogLevel.verbose);
    }
    cloud.log(deviceId, '$displayName: disconnected, not active', level: LogLevel.verbose);
  }

  Future<Null> _connect(Sink<int> sink) async {
    cloud.log(deviceId, '$displayName: attempting connection...', level: LogLevel.verbose);
    HttpClientResponse response;
    try {
      final HttpClientRequest request = await cloud.openRequest('get', 'https://api-http.littlebitscloud.cc/v2/devices/$deviceId/input');
      response = await request.close();
    } catch (error, stack) {
      cloud.log(deviceId, 'unexpected error: $error');
      cloud.log(deviceId, stack.toString(), level: LogLevel.verbose);
      return _error(error);
    }
    assert(response != null);
    switch (response.statusCode) {
      case 429:
        cloud.log(deviceId, '$displayName: 429 rate-limit; delaying ${cloud.rateLimitDelay}', level: LogLevel.verbose);
        await response.drain();
        return _error(new CloudBitRateLimitException(this), cloud.rateLimitDelay);
      case 404:
        final String message = await response.transform(utf8.decoder).join();
        cloud.log(deviceId, '$displayName: not connected; delaying ${cloud.noConnectionDelay}: 404, $message', level: LogLevel.verbose);
        // no need to drain since we read the message above
        return _error(new CloudBitNotConnected(this, 'attempting to connect to listen to data'), cloud.noConnectionDelay);
      case 200:
        cloud.log(deviceId, '$displayName: connected', level: LogLevel.verbose);
        break;
      default:
        cloud.log(deviceId, '$displayName: contract violation: $response');
        await response.drain();
        return _error(new CloudBitContractViolation('unexpected error from littlebits cloud (${response.statusCode} ${response.reasonPhrase})', this));
    }
    Completer<Null> completer = new Completer<Null>();
    _events = response
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(new StreamTransformer<String, dynamic>.fromHandlers(
        handleData: (String data, EventSink<dynamic> sink) {
          if (data.isEmpty)
            return;
          if (data.startsWith('data:')) {
            try {
              sink.add(json.decode(data.substring(5))); // 5 is the length of the string 'data:'
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
                cloud._reportError(exception: new CloudBitNotConnected(this, 'listening for data'), connected: wasConnected);
                cloud.log(deviceId, json.encode(event), level: LogLevel.verbose);
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
          cloud.log(deviceId, '$displayName: got exception from events stream: $exception');
          cloud.log(deviceId, stack.toString(), level: LogLevel.verbose);
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
    cloud.log(deviceId, '$displayName: reporting error "$exception" (${_active ? "still active" : "now inactive"})', level: LogLevel.verbose);
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
        cloud.log(deviceId, '$displayName: post-error continuation (${_active ? "still active" : "now inactive"})', level: LogLevel.verbose);
        completer.complete();
      },
    );
    assert(!_connected);
    return completer.future;
  }

  bool _connected = false;

  void _emit(int value) {
    if (_connected != (value != null))
      cloud.log(deviceId, '$displayName: ${value == null ? "disconnected" : "connected"}', level: LogLevel.verbose);
    _connected = value != null;
    _valueStream.add(value);
  }

  void _end() {
    cloud.log(deviceId, '$displayName: disconnecting.', level: LogLevel.verbose);
    _active = false;
    _events?.cancel();
    _events = null;
  }

  @override
  void dispose() {
    cloud.log(deviceId, '$displayName: disposing...', level: LogLevel.verbose);
    _end();
    _valueStream.close();
  }
}
