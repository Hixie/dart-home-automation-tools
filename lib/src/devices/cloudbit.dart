import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../metrics.dart';
import '../temperature.dart';
import '../watch_stream.dart';

enum LedColor { black, blue, red, purple, green, teal, yellow, white }

class CloudBitException implements Exception {
  const CloudBitException(this.message, this.cloudbit);
  final String message;
  final CloudBit cloudbit;
  @override
  String toString() => '$message (${cloudbit?.displayName})';
}

abstract class CloudBitProvider {
  CloudBitProvider({
    this.onLog,
    this.onError, // if not specified, defers to onLog
  });

  final DeviceLogCallback onLog;
  final ErrorHandler onError;

  Future<CloudBit> getDevice(String deviceId);

  void dispose();

  void log(String deviceId, String message, { LogLevel level: LogLevel.info }) {
    if (onLog != null && level.index <= LogLevel.info.index)
      onLog(deviceId, message);
  }

  void reportError(CloudBitException error) {
    if (onError != null) {
      onError(error);
    } else {
      log(error.cloudbit?.deviceId, error.message, level: LogLevel.error);
    }
  }
}

abstract class CloudBit {
  String get deviceId;
  String get displayName;

  /// Set the cloudbit output value. The range is 0x0000 to 0xFFFF.
  void set16bitValue(int value, { bool silent: false });

  /// Set the cloudbit output value. The range is 0..1023.
  void setValue(int value, { Duration duration, bool silent: false });

  /// Set the cloudbit output value such that it will display `value`
  /// on an o21 number bit in "value" mode. Range is 0..99.
  ///
  /// See [setValue].
  void setNumberValue(int value, { Duration duration, bool silent: false });

  /// Set the cloudbit output value such that it will display `value`
  /// on an o21 number bit in "volts" mode. Range is 0.0..5.0.
  ///
  /// See [setValue].
  void setNumberVolts(double value, { Duration duration, bool silent: false });

  /// Set the cloudbit output value such that it will turn the output
  /// entirely on or off.
  ///
  /// See [setValue].
  void setBooleanValue(bool value, { Duration duration, bool silent: false });

  void setLedColor(LedColor color);

  /// The current value, in the range 0..1023.
  Stream<int> get values;

  Stream<bool> get button;

  void dispose();

  @override
  String toString() => '$runtimeType($displayName, $deviceId)';
}

typedef void DebugObserver(int value);

class BitDemultiplexer {
  BitDemultiplexer(this.input, this.bitCount, { this.onDebugObserver }) {
    assert(bitCount >= 2);
    assert(bitCount <= 4);
  }

  final Stream<int> input;
  final int bitCount;

  final DebugObserver onDebugObserver;

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
      if (onDebugObserver != null)
        onDebugObserver(bitfield);
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
  TemperatureSensor.F(this._value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : _valueIsF = true,
       super(station: station, timestamp: timestamp);

  TemperatureSensor.C(this._value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : _valueIsF = false,
       super(station: station, timestamp: timestamp);

  final int _value; // 0..1024
  final bool _valueIsF;
  @override
  double get fahrenheit => _valueIsF ? 100.0 * _value / 1023.0 : celsius * 9.0 / 5.0 + 32.0;
  @override
  double get celsius => _valueIsF ? (fahrenheit - 32.0) * 5.0 / 9.0 : 100.0 * _value / 1023.0;
}

StreamHandler<int> getRawValueDiskLogger({
  @required String name,
  @required File log,
}) {
  return (int value) {
    String number = '-';
    if (value != null)
      number = ((value / 1023.0) * 99.0).toStringAsFixed(1);
    log.openWrite(mode: FileMode.append)
      ..writeln('$name,${new DateTime.now().toIso8601String().padRight(26, '0')},$value,$number')
      ..close();
  };
}

StreamHandler<int> getAverageValueLogger({
  @required LogCallback log,
  @required String name,
  double slop: 1023.0 * 0.01, // 1% of total range
  double reportingThreshold: 1023.0 * 0.001, // 0.1% of total range
  File diskLog,
}) {
  bool connected = false;
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
      log('cloudbit raw value $value [${(value / 1023.0 * 99.0).round()}], far outside previous average (${average?.toStringAsFixed(1)})');
      average = value.toDouble();
      countedValues = 1;
    } else {
      final double oldAverage = average;
      average = (average * countedValues + value) / (countedValues.toDouble() + 1.0);
      countedValues += 1;
      if ((oldAverage - average).abs() > reportingThreshold)
        log('cloudbit raw value $value [${(value / 1023.0 * 99.0).round()}], new average is ${average.toStringAsFixed(1)} [${(average / 1023.0 * 99.0).round()}]');
    }
  };
}
