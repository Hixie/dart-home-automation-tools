import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'common.dart';
import 'cloudbit.dart';
import 'watch_stream.dart';

class LocalCloudBitDeviceDescription {
  const LocalCloudBitDeviceDescription(this.displayName, this.hostname);
  final String displayName;
  final String hostname;
}

typedef LocalCloudBitDeviceDescription LocalHostIdentifier(String deviceId);

class LittleBitsLocalServer extends CloudBitProvider {
  LittleBitsLocalServer({
    this.onIdentify,
    this.onError,
    DeviceLogCallback onLog,
  }) : super(
    onLog: onLog,
  ) {
    _initialize();
  }

  final LocalHostIdentifier onIdentify;
  final ErrorHandler onError;

  final Map<String, _CloudBit> _devices = <String, _CloudBit>{};
  RawDatagramSocket _socket;
  Completer<Null> _ready = new Completer<Null>();

  Future<Null> _initialize() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, 2020);
    _socket.listen(_listener);
    _ready.complete();
    log(null, 'initialized littlebits local cloud manager');
    return _ready.future;
  }

  void _listener(RawSocketEvent event) {
    Datagram d = _socket.receive();
    if (d == null)
      return;
    for (_CloudBit cloudbit in _devices.values)
      cloudbit._listener(d);
  }

  @override
  Future<CloudBit> getDevice(String deviceId) async {
    final _CloudBit cloudbit = _devices.putIfAbsent(deviceId, () {
      LocalCloudBitDeviceDescription description = onIdentify(deviceId);
      log(deviceId, 'adding "${description.displayName}" to cloudbit library ($deviceId, ${description.hostname})', level: LogLevel.verbose);
      return new _CloudBit._(this, deviceId, description.displayName, description.hostname);
    });
    return _ready.future.then((Null value) => cloudbit);
  }

  @override
  void dispose() {
    _socket.close();
    for (_CloudBit cloudbit in _devices.values)
      cloudbit.dispose();
  }
}

class _CloudBit extends CloudBit {
  _CloudBit._(this.server, this.deviceId, this.displayName, this.hostname) : _macAddressBytes = _parseMac(deviceId);

  final LittleBitsLocalServer server;

  @override
  final String deviceId;
  final Uint8List _macAddressBytes;

  @override
  final String displayName;

  final String hostname;

  Timer _refreshTimer;
  Timer _resetTimer;
  int _value;
  int _color;

  bool _ready = false;

  static Uint8List _parseMac(String deviceId) {
    Uint8List result = new Uint8List(8); // room for a 64 bit integer
    new ByteData.view(result.buffer).setUint64(0, int.parse(deviceId, radix: 16) << 16, Endianness.BIG_ENDIAN);
    return result.sublist(0, 6); // MAC addresses are only actually 48 bits
  }

  void _listener(Datagram d) {
    if (d.data.length >= 9 &&
        d.data[0] == _macAddressBytes[0] &&
        d.data[1] == _macAddressBytes[1] &&
        d.data[2] == _macAddressBytes[2] &&
        d.data[3] == _macAddressBytes[3] &&
        d.data[4] == _macAddressBytes[4] &&
        d.data[5] == _macAddressBytes[5]) {
      _buttonStream.add((d.data[7] & 0x01) > 0);
      _valuesStream.add((((d.data[8] << 8) + d.data[9]) * 1024 / 0xFFFF).round());
    }
  }

  void _sendValue(int value, { Duration duration, bool silent: false }) {
    _value = value.clamp(0x0000, 0xFFFF);
    if (!silent)
      server.log(deviceId, '$displayName: sending 0x${_value.toRadixString(16).padLeft(4, "0")}${ duration != null ? " (${duration.inMilliseconds}ms)" : ""}');
    scheduleMicrotask(_refreshValue);
    _resetTimer?.cancel();
    _resetTimer = null;
    if (duration != null) {
      _resetTimer = new Timer(duration, () {
        _value = 0;
        _refreshValue();
      });
    }
  }

  bool _sending = false;

  Future<Null> _refreshValue() async {
    if (_sending)
      return;
    _sending = true;
    if (_refreshTimer == null)
      _refreshTimer = new Timer.periodic(const Duration(minutes: 1), (Timer timer ) { _refreshValue(); });
    try {
      List<InternetAddress> hosts = await InternetAddress.lookup(hostname, type: InternetAddressType.IP_V4)
        .timeout(const Duration(seconds: 30));
      if (hosts.isEmpty) {
        server.log(deviceId, '$displayName: failed to resolve "$hostname"');
        return;
      }
      Uint8List buffer = new Uint8List(6 + 2 + 2);
      buffer.setRange(0, _macAddressBytes.length, _macAddressBytes);
      buffer[6] = _color != null ? 0x80 | _color : 0x00; // LED
      if (_value != null) {
        buffer[7] = 0x80; // Set Value
        buffer[8] = (_value >> 8) & 0xFF;
        buffer[9] = _value & 0xFF;
      } else {
        buffer[7] = 0x00;
        buffer[8] = 0x00;
        buffer[9] = 0x00;
      }
      server._socket.send(buffer, hosts.first, 2021);
    } finally {
      _sending = false;
    }
  }

  @override
  void set16bitValue(int value, { Duration duration, bool silent: false }) {
    assert(value != null);
    _sendValue(value, duration: duration, silent: silent);
  }

  @override
  void setValue(int value, { Duration duration, bool silent: false }) {
    assert(value != null);
    _sendValue(((value * 0xFFFF) / 1023.0).round(), duration: duration, silent: silent);
  }

  @override
  void setNumberValue(int value, { Duration duration, bool silent: false }) {
    assert(value != null);
    _sendValue(((value * 0xFFFF) / 99.0).round(), duration: duration, silent: silent);
  }

  @override
  void setNumberVolts(double value, { Duration duration, bool silent: false }) {
    assert(value != null);
    _sendValue(((value * 0xFFFF) / 5.0).round(), duration: duration, silent: silent);
  }

  @override
  void setBooleanValue(bool value, { Duration duration, bool silent: false }) {
    assert(value != null);
    _sendValue(value ? 0xFFFF : 0x0000, duration: duration, silent: silent);
  }

  @override
  void setLedColor(LedColor color) {
    assert(color != null);
    server.log(deviceId, '$displayName: sending $color', level: LogLevel.verbose);
    _color = color.index;
    scheduleMicrotask(_refreshValue);
  }

  WatchStream<int> _valuesStream = new AlwaysOnWatchStream<int>();
  WatchStream<bool> _buttonStream = new AlwaysOnWatchStream<bool>();

  @override
  Stream<int> get values => _valuesStream;

  @override
  Stream<bool> get button => _buttonStream;

  @override
  void dispose() {
    _refreshTimer.cancel();
    _resetTimer?.cancel();
    _valuesStream.close();
    _buttonStream.close();
  }
}
