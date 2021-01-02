import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../json.dart';
import '../url_watch_stream.dart';
import '../metrics.dart';

/// See https://docs.airnowapi.org/Data/query
class AirNowAirQualityMonitor {
  AirNowAirQualityMonitor({ @required GeoBox area, @required String apiKey, this.onLog }) {
    assert(area != null);
    assert(apiKey != null);
    _client = new HttpClient();
    final String url = 'http://www.airnowapi.org/aq/data/?parameters=O3,PM25,PM10,CO,NO2,SO2&BBOX=$area&dataType=B&format=application/json&verbose=1&API_KEY=$apiKey';
    _dataStream = new UrlWatchStream<MeasurementPacket>(_client, const Duration(minutes: 15), _decodeData, onLog, url: url);
  }

  HttpClient _client;

  final LogCallback onLog;

  Stream<MeasurementPacket> get dataStream => _dataStream;
  UrlWatchStream<MeasurementPacket> _dataStream;

  MeasurementPacket _decodeData(String value) {
    List<AirQualityParameter> parameters = <AirQualityParameter>[];
    try {
      for (dynamic entry in Json.parse(value).asIterable()) {
        parameters.add(new AirNowAirQualityParameter(
          station: new MeasurementStation(
            latitude: entry.Latitude.toDouble(),
            longitude: entry.Longitude.toDouble(),
            siteName: entry.SiteName.toString(),
            agencyName: entry.AgencyName.toString(),
            aqsCode: entry.FullAQSCode.toString(),
            internationalAqsCode: entry.internationalAqsCode.toString(),
            outside: true,
          ),
          timestamp: DateTime.parse('${entry.UTC}Z'),
          parameterName: entry.Parameter.toString(),
          unitsName: entry.Unit.toString(),
          value: entry.Value.toDouble(),
          aqi: _filterAqi(entry.AQI.toDouble()),
          category: entry.Category.toInt(),
        ));
      }
      return new MeasurementPacket(parameters);
    } catch (error) {
      throw new Exception('While trying to parse air quality payload: $error');
    }
  }

  static double _filterAqi(double aqi) {
    if (aqi < 0.0)
      return null;
    return aqi;
  }

  void dispose() {
    _dataStream.close();
    _dataStream = null;
    _client.close(force: true);
  }
}

class AirNowAirQualityParameter extends AirQualityParameter {
  AirNowAirQualityParameter({
    MeasurementStation station,
    DateTime timestamp,
    String parameterName,
    String unitsName,
    double value,
    double aqi,
    this.category,
  }) : super(
         station: station,
         timestamp: timestamp,
         metric: identifyParameter(parameterName),
         units: identifyUnits(unitsName),
         value: value,
         aqi: aqi,
       );

  final int category;

  static Metric identifyParameter(String parameterName) {
    switch (parameterName) {
      case 'OZONE': return Metric.ozone;
      case 'PM2.5': return Metric.pm2_5;
      case 'PM10': return Metric.pm10;
      case 'CO': return Metric.carbonMonoxide;
      case 'NO2': return Metric.nitrogenDioxide;
      case 'SO2': return Metric.sulphurDioxide;
    }
    throw 'Unknown air quality metric "$parameterName".';
  }

  static MetricUnits identifyUnits(String unitsName) {
    switch (unitsName) {
      case 'UG/M3': return MetricUnits.microgramsPerCubicMeter;
      case 'PPM': return MetricUnits.partsPerMillion;
      case 'PPB': return MetricUnits.partsPerBillion;
    }
    throw 'Unknown units "$unitsName".';
  }
}

class GeoBox {
  const GeoBox(this.minLat, this.minLong, this.maxLat, this.maxLong);
  final double minLat;
  final double minLong;
  final double maxLat;
  final double maxLong;
  @override
  String toString() => '${minLat.toStringAsFixed(6)},${minLong.toStringAsFixed(6)},${maxLat.toStringAsFixed(6)},${maxLong.toStringAsFixed(6)}';
}
