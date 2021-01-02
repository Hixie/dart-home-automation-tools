import 'dart:async';
import 'dart:io';

import '../common.dart';
import '../metrics.dart';
import '../temperature.dart';
import '../watch_stream.dart';

class OneWireTemperature {
  OneWireTemperature({
    this.id,
    this.station,
    this.period: const Duration(seconds: 10),
    this.onLog,
    this.onError,
  }) {
    _temperature = new HandlerWatchStream<Temperature>(_start, _end, staleTimeout: period + const Duration(seconds: 5));
    _tick(null);
  }

  final String id;
  final MeasurementStation station;
  final Duration period;
  final LogCallback onLog;
  final ErrorHandler onError;

  WatchStream<Temperature> _temperature;
  WatchStream<Temperature> get temperature => _temperature;
  
  Timer _timer;

  String get _filename => '/sys/bus/w1/devices/28-$id/w1_slave';

  void _start(Sink<Temperature> sink) {
    assert(_timer == null);
    _timer = new Timer.periodic(period, _tick);
  }

  void _end() {
    assert(_timer != null);
    _timer.cancel();
    _timer = null;
  }

  Future<Null> _tick(Timer timer) async {
    try {
      final File file = new File(_filename);
      if (!file.existsSync())
        throw new Exception('could not find "$_filename" (raw data for 1-wire sensor "$id")');
      final String raw = file.readAsStringSync();
      final DateTime timestamp = new DateTime.now();
      final List<String> lines = raw.split('\n');
      if (lines.isEmpty)
        throw new Exception('no data from thermal sensor');
      if (lines[0].length < 27)
        throw new Exception('incomplete data from thermal sensor');
      if (lines[0][27] != ':')
        throw new Exception('incorrect format of crc check from thermal sensor');
      if (lines[0].substring(36) != 'YES')
        throw new Exception('thermal sensor data crc mismatch');
      if (lines[1].substring(27, 29) != 't=')
        throw new Exception('incorrect format of data from thermal sensor');
      double celsius = int.parse(lines[1].substring(29)) / 1000.0;
      if (celsius == 85.0)
        throw new Exception('thermal sensor rebooting');
      temperature.add(new RawTemperature(celsius, station: station, timestamp: timestamp));
    } catch (error) {
      await fail(error);
    }
  }

  Future<Null> fail(dynamic error) async {
    if (onError != null)
      await onError(error);
  }

  void dispose() {
    _temperature.close();
    _timer?.cancel();
  }
}
