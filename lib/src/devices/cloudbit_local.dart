import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common.dart';
import '../watch_stream.dart';
import 'cloudbit.dart';

class LocalCloudBitDeviceDescription {
  const LocalCloudBitDeviceDescription(this.displayName, this.hostname);
  final String displayName;
  final String hostname;
}

typedef LocalCloudBitDeviceDescription LocalHostIdentifier(String deviceId);

class LittleBitsLocalServer extends CloudBitProvider {
  LittleBitsLocalServer({
    this.onIdentify,
    DeviceLogCallback onLog,
  }) : super(
    onLog: onLog,
  ) {
    _initialize();
  }

  final LocalHostIdentifier onIdentify;

  final Map<String, Localbit> _devices = <String, Localbit>{};
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
    for (Localbit cloudbit in _devices.values)
      cloudbit._listener(d);
  }

  @override
  Future<CloudBit> getDevice(String deviceId) async {
    final Localbit cloudbit = _devices.putIfAbsent(deviceId, () {
      LocalCloudBitDeviceDescription description = onIdentify(deviceId);
      log(deviceId, 'adding "${description.displayName}" to cloudbit library ($deviceId, ${description.hostname})', level: LogLevel.verbose);
      return new Localbit._(this, deviceId, description.displayName, description.hostname);
    });
    return _ready.future.then((Null value) => cloudbit);
  }

  @override
  void dispose() {
    _socket.close();
    for (Localbit cloudbit in _devices.values)
      cloudbit.dispose();
  }
}

class Localbit extends CloudBit {
  Localbit._(this.server, this.deviceId, this.displayName, this.hostname) : _macAddressBytes = _parseMac(deviceId);

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
      Uint8List buffer = new Uint8List(6 + 2 + 2);
      buffer[6] = _color != null ? 0x80 | _color : 0x00; // LED
      if (_value != null) {
        buffer[7] = 0x80; // value mode
        buffer[8] = (_value >> 8) & 0xFF;
        buffer[9] = _value & 0xFF;
      } else {
        buffer[7] = 0x00;
        buffer[8] = 0x00;
        buffer[9] = 0x00;
      }
      await _addMacAndTransmit(buffer);
    } finally {
      _sending = false;
    }
  }

  Future<Null> _addMacAndTransmit(Uint8List buffer) async {
    try {
      List<InternetAddress> hosts = await InternetAddress.lookup(hostname, type: InternetAddressType.IP_V4)
        .timeout(const Duration(seconds: 30));
      if (hosts.isEmpty) {
        server.log(deviceId, '$displayName: failed to resolve "$hostname"');
        return;
      }
      assert(buffer.length >= 6);
      assert(buffer[0] == 0x00);
      assert(buffer[1] == 0x00);
      assert(buffer[2] == 0x00);
      assert(buffer[3] == 0x00);
      assert(buffer[4] == 0x00);
      assert(buffer[5] == 0x00);
      buffer.setRange(0, _macAddressBytes.length, _macAddressBytes);
      server._socket.send(buffer, hosts.first, 2021);
    } catch (exception) {
      server.log(deviceId, '$displayName: failed to send message to "$hostname": $exception');
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

  Uint8List _concatenate(Uint8List list1, Uint8List list2, [ Uint8List list3 ]) {
    int newLength = list1.length + list2.length;
    if (list3 != null)
      newLength += list3.length;
    Uint8List result = new Uint8List(newLength);
    result.setRange(0, list1.length, list1);
    result.setRange(list1.length, list1.length + list2.length, list2);
    if (list3 != null)
      result.setRange(list1.length + list2.length, list1.length + list2.length + list3.length, list3);
    return result;
  }

  // SERIAL OUTPUT (LOCALBIT ONLY)

  void sendSerialData(Uint8List message) {
    assert(message != null);
    assert(message.length <= 260);
    server.log(deviceId, '$displayName: sending ${message.length} byte serial data message', level: LogLevel.verbose);
    Uint8List header = new Uint8List(6 + 2 + 2);
    header[6] = _color != null ? 0x80 | _color : 0x00; // LED
    header[7] = 0x40; // serial data mode
    header[8] = (message.length >> 8) & 0xFF;
    header[9] = message.length & 0xFF;
    _value = 0xFFFF;
    _addMacAndTransmit(_concatenate(header, message));
  }

  void sendLEDMatrixMessage(MatrixMessageType messageType, MatrixPresentation presentation, Uint8List data) {
    assert(messageType != null);
    assert(presentation != null);
    assert(data.length < 256);
    Uint8List preamble = new Uint8List(4);
    preamble[0] = 0x1C;
    preamble[1] = messageType.asByte();
    preamble[2] = presentation.asByte();
    preamble[3] = data.length;
    Uint8List postamble = new Uint8List(1);
    postamble[0] = 0x26;
    sendSerialData(_concatenate(preamble, data, postamble));
  }

  void sendText(String message, { int color: 0xFF, int scrollOffset: 0, MatrixPresentation presentation: MatrixPresentation.one }) {
    assert(message != null);
    assert(message.length < 256 - 3);
    assert(color != null);
    assert(color >= 0x00);
    assert(color <= 0xFF);
    assert(scrollOffset != null);
    assert(scrollOffset >= 0x0000);
    assert(scrollOffset <= 0xFFFF);
    assert(presentation != null);
    Uint8List payload = new Uint8List(3);
    payload[0] = color;
    payload[1] = (scrollOffset >> 8) & 0xFF;
    payload[2] = scrollOffset & 0xFF;
    sendLEDMatrixMessage(MatrixMessageType.text, presentation, _concatenate(payload, ASCII.encode(message)));
  }

  void sendImage(MatrixBitmap image, { MatrixPresentation presentation: MatrixPresentation.one }) {
    assert(image != null);
    assert(presentation != null);
    sendLEDMatrixMessage(MatrixMessageType.image, presentation, image.asBytes());
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

class MatrixMessageType {
  MatrixMessageType(this.id) {
    assert(id != null);
    assert(id == 0x00 || id == 0x01);
  }

  MatrixMessageType.experimental(this.id) {
    assert(id != null);
    assert(id >= 0x00);
    assert(id <= 0xFF);
  }

  const MatrixMessageType._(this.id);

  static const MatrixMessageType image = const MatrixMessageType._(0x00);

  static const MatrixMessageType text = const MatrixMessageType._(0x01);

  final int id;

  int asByte() => id;
}

class MatrixPresentation {
  MatrixPresentation({
    @required this.channelCount,
    this.channel1: false,
    this.channel2: false,
    this.channel3: false,
    this.channel4: false,
  }) {
    assert(channelCount != null);
    assert(channelCount > 0);
    assert(channelCount <= 4);
    assert(channel1 != null);
    assert(channel2 != null);
    assert(channel3 != null);
    assert(channel4 != null);
  }

  MatrixPresentation.experimental({
    @required this.channelCount,
    this.channel1: false,
    this.channel2: false,
    this.channel3: false,
    this.channel4: false,
  }) {
    assert(channelCount != null);
    assert(channelCount >= 0x0);
    assert(channelCount <= 0xF);
    assert(channel1 != null);
    assert(channel2 != null);
    assert(channel3 != null);
    assert(channel4 != null);
  }

  const MatrixPresentation._({
    @required this.channelCount,
    this.channel1: false,
    this.channel2: false,
    this.channel3: false,
    this.channel4: false,
  });

  static const MatrixPresentation one = const MatrixPresentation._(channelCount: 1, channel1: true);

  final int channelCount;

  final bool channel1;

  final bool channel2;

  final bool channel3;

  final bool channel4;

  int asByte() {
    return (channelCount << 4) +
           (channel4 ? 0x08 : 0x00) +
           (channel3 ? 0x04 : 0x00) +
           (channel2 ? 0x02 : 0x00) +
           (channel1 ? 0x01 : 0x00);
  }
}

class MatrixBitmap {
  MatrixBitmap(this.data) {
    assert(data != null);
    assert(data.length == 64);
  }

  MatrixBitmap.fromList(List<int> pixels) : data = new Uint8List.fromList(pixels) {
    assert(pixels != null);
    assert(pixels.length == 64);
  }

  MatrixBitmap.fillColor(int color) : data = new Uint8List(64)..fillRange(0, 64, color) {
    assert(color != null);
    assert(color >= 0x00);
    assert(color <= 0xFF);
  }

  MatrixBitmap.black() : data = new Uint8List(64);

  final Uint8List data;

  Uint8List asBytes() => data;

  void drawRect(int left, int top, int width, int height, int color) {
    assert(left != null);
    assert(left >= 0);
    assert(left < 8);
    assert(top != null);
    assert(top >= 0);
    assert(top < 8);
    assert(width != null);
    assert(width > 0);
    assert(left + width >= 0);
    assert(left + width < 8);
    assert(height != null);
    assert(height > 0);
    assert(top + height >= 0);
    assert(top + height < 8);
    assert(color != null);
    assert(color >= 0x00);
    assert(color <= 0xFF);
    for (int y = top; y < top + height; y += 1)
      data.fillRange(y * 8 + left, y * 8 + left + width, color);
  }

  void drawPoint(int x, int y, int color) {
    assert(x != null);
    assert(x >= 0);
    assert(x < 8);
    assert(y != null);
    assert(y >= 0);
    assert(y < 8);
    assert(color != null);
    assert(color >= 0x00);
    assert(color <= 0xFF);
    data[y * 8 + x] = color;
  }
}
