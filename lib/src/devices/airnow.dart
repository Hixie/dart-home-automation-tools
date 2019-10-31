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
    _airStream = new UrlWatchStream<AirQuality>(_client, const Duration(minutes: 15), _decodeData, onLog, url: url);
  }

  HttpClient _client;

  final LogCallback onLog;

  Stream<AirQuality> get value => _airStream;
  UrlWatchStream<AirQuality> _airStream;

  AirQuality _decodeData(String value) {
    List<AirQualityParameter> parameters = <AirQualityParameter>[];
    try {
      for (Json entry in Json.parse(value).asIterable()) {
        parameters.add(new AirQualityParameter(
          station: new AirQualityStation(
            latitude: entry.Latitude.toDouble(),
            longitude: entry.Longitude.toDouble(),
            siteName: entry.SiteName.toString(),
            agencyName: entry.AgencyName.toString(),
            aqsCode: entry.FullAQSCode.toString(),
            internationalAqsCode: entry.internationalAqsCode.toString(),
          ),
          timestamp: DateTime.parse('${entry.UTC}Z'),
          parameterName: entry.Parameter.toString(),
          unitsName: entry.Unit.toString(),
          value: entry.Value.toDouble(),
          aqi: entry.AQI.toDouble(),
          category: entry.Category.toInt(),
        ));
      }
      return new AirQuality(parameters);
    } catch (error) {
      throw new Exception('While trying to parse air quality payload: $error');
    }
  }

  void dispose() {
    _airStream.close();
    _airStream = null;
    _client.close(force: true);
  }
}
