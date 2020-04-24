import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../json.dart';
import '../metrics.dart';
import '../radiation.dart';
import '../temperature.dart';
import '../url_watch_stream.dart';

class URadMonitor {
  URadMonitor({
    @required this.host,
    @required this.station,
    Duration period: const Duration(seconds: 30),
    this.onLog,
  }) {
    assert(host != null);
    assert(station != null);
    _client = new HttpClient();
    _dataStream = new UrlWatchStream<MeasurementPacket>(_client, period, _handleData, onLog, url: 'http://$host/j');
  }

  final String host;
  final MeasurementStation station;
  Duration get period => _dataStream.period;
  final LogCallback onLog;

  HttpClient _client;

  UrlWatchStream<MeasurementPacket> _dataStream;
  Stream<MeasurementPacket> get dataStream => _dataStream;

  MeasurementPacket _handleData(String value) {
    final DateTime timestamp = new DateTime.now();
    try {
      dynamic data = Json.parse(value).data;
      if (data.type.toString() != '8')
        throw 'unknown device type';
      List<Measurement> parameters = <Measurement>[
        new URadMonitorRadiation(
          station: station,
          timestamp: timestamp,
          detector: data.detector.toString(),
          countsPerMinute: data.cpm.toInt(),
        ),
        new RawTemperature(data.temperature.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.humidity(data.humidity.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.pressure(data.pressure.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.volatileOrganicCompounds(data.voc.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.carbonDioxide(data.co2.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.noise(data.noise.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.formaldehyde(data.ch2o.toDouble(), station: station, timestamp: timestamp),
        new AirQualityParameter.pm2_5(data.pm25.toDouble(), station: station, timestamp: timestamp),
      ];
      return new MeasurementPacket(parameters);
    } catch (error) {
      throw new Exception('unexpected data from uRADMonitor: $value (failed with $error)');
    }
  }

  void log(String message) {
    if (onLog != null)
      onLog(message);
  }

  void dispose() {
    _dataStream.close();
    _dataStream = null;
    _client.close(force: true);
  }
}

class URadMonitorRadiation extends Radiation {
  URadMonitorRadiation({
    @required MeasurementStation station,
    @required DateTime timestamp,
    @required String detector,
    @required this.countsPerMinute,
  }) : doseRate = _detectorFactor(detector) * countsPerMinute,
       super(station: station, timestamp: timestamp);

  final int countsPerMinute;

  @override
  final double doseRate; // approximation
  
  static double _detectorFactor(String detector) {
    switch (detector) {
      case 'SBM20':
        return 0.006315;
      case 'SI29BG':
        return 0.010000;
      case 'SBM19':
        return 0.001500;
      case 'LND712':
        return 0.005940;
      case 'SBM20M':
        return 0.013333;
      case 'SI22G':
        return 0.001714;
      case 'STS5':
        return 0.006666;
      case 'SI3BG':
        return 0.631578;
      case 'SBM21':
        return 0.048000;
      case 'SBT9':
        return 0.010900;
      case 'SI1G':
        return 0.006000;
      case 'SI8B':
        return 0.001108;
      case 'SBT10A':
        return 0.001105;
      default:
        throw 'unknown detector "$detector"';
    }
  }
}
