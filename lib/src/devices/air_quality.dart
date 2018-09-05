import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:meta/meta.dart';

import 'common.dart';
import 'hash_codes.dart';
import 'json.dart';
import 'url_watch_stream.dart';

class AirQualityStation {
  const AirQualityStation({ this.latitude, this.longitude, this.siteName, this.agencyName, this.aqsCode, this.internationalAqsCode });

  final double latitude;
  final double longitude;
  final String siteName;
  final String agencyName;
  final String aqsCode;
  final String internationalAqsCode;

  @override
  String toString() => siteName ?? agencyName ?? aqsCode ?? internationalAqsCode ?? '$latitude,$longitude';

  @override
  int get hashCode => hashValues(latitude, longitude, siteName, agencyName, aqsCode, internationalAqsCode);

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType)
      return false;
    AirQualityStation typedOther = other;
    return typedOther.latitude == latitude
        && typedOther.longitude == longitude
        && typedOther.siteName == siteName
        && typedOther.agencyName == agencyName
        && typedOther.aqsCode == aqsCode
        && typedOther.internationalAqsCode == internationalAqsCode;
  }
}

enum AirQualityMetric {
  ozone,
  pm2_5,
  pm10,
  carbonMonoxide,
  nitrogenDioxide,
  sulphurDioxide,
}

enum AirQualityUnits {
  microgramsPerCubicMeter,
  partsPerMillion,
  partsPerBillion,
}

@immutable
class AirQualityParameter {
  AirQualityParameter({
    this.station,
    this.timestamp,
    AirQualityMetric metric,
    this.parameterName,
    AirQualityUnits units,
    this.unitsName,
    this.value,
    double aqi,
    this.category,
  }) : metric = metric ?? identifyParameter(parameterName),
       units = units ?? identifyUnits(unitsName),
       aqi = aqi >= 0.0 ? aqi : null;

  static AirQualityMetric identifyParameter(String parameterName) {
    switch (parameterName) {
      case 'OZONE': return AirQualityMetric.ozone;
      case 'PM2.5': return AirQualityMetric.pm2_5;
      case 'PM10': return AirQualityMetric.pm10;
      case 'CO': return AirQualityMetric.carbonMonoxide;
      case 'NO2': return AirQualityMetric.nitrogenDioxide;
      case 'SO2': return AirQualityMetric.sulphurDioxide;
    }
    return null;
  }

  static AirQualityUnits identifyUnits(String parameterName) {
    switch (parameterName) {
      case 'UG/M3': return AirQualityUnits.microgramsPerCubicMeter;
      case 'PPM': return AirQualityUnits.partsPerMillion;
      case 'PPB': return AirQualityUnits.partsPerBillion;
    }
    return null;
  }

  final AirQualityStation station;
  final DateTime timestamp;
  final AirQualityMetric metric;
  final String parameterName;
  final AirQualityUnits units;
  final String unitsName;
  final double value;
  final double aqi;
  final int category;

  @override
  String toString() {
    StringBuffer result = new StringBuffer();
    if (metric != null) {
      switch (metric) {
        case AirQualityMetric.ozone:
          result.write('O₃: ');
          break;
        case AirQualityMetric.pm2_5:
          result.write('PM₂.₅: ');
          break;
        case AirQualityMetric.pm10:
          result.write('PM₁₀: ');
          break;
        case AirQualityMetric.carbonMonoxide:
          result.write('CO: ');
          break;
        case AirQualityMetric.nitrogenDioxide:
          result.write('NO₂: ');
          break;
        case AirQualityMetric.sulphurDioxide:
          result.write('SO₂: ');
          break;
      }
    } else if (parameterName != null) {
      result.write('$parameterName: ');
    }
    if (value != null) {
      result.write(value.toStringAsFixed(2));
      if (units != null) {
        switch (units) {
          case AirQualityUnits.microgramsPerCubicMeter:
            result.write('µg/m³');
            break;
          case AirQualityUnits.partsPerMillion:
            result.write('ppm');
            break;
          case AirQualityUnits.partsPerBillion:
            result.write('ppb');
            break;
        }
      } else if (unitsName != null) {
        result.write('$unitsName');
      }
    }
    if (aqi != null) {
      if (value != null)
        result.write(' (');
      result.write('AQI ${aqi.toStringAsFixed(0)}');
      if (value != null)
        result.write(')');
    }
    return result.toString();
  }
}

class AirQuality {
  AirQuality(List<AirQualityParameter> parameters) {
    _parameters = parameters;
    _stations = new HashSet<AirQualityStation>();
    _metrics = new HashMap<AirQualityMetric, AirQualityParameter>();
    for (AirQualityParameter parameter in parameters) {
      _earliestTimestamp = min(_earliestTimestamp, parameter.timestamp);
      _latestTimestamp = max(_latestTimestamp, parameter.timestamp);
      _stations.add(parameter.station);
      _metrics.putIfAbsent(parameter.metric, () => parameter);
    }
  }

  DateTime get timestamp => _earliestTimestamp == _latestTimestamp ? _earliestTimestamp : null;
  DateTime get earliestTimestamp => _earliestTimestamp;
  DateTime _earliestTimestamp;
  DateTime get latestTimestamp => _latestTimestamp;
  DateTime _latestTimestamp;

  Iterable<AirQualityParameter> get parameters => _parameters;
  List<AirQualityParameter> _parameters;

  Iterable<AirQualityStation> get stations => _stations;
  Set<AirQualityStation> _stations;

  AirQualityParameter get ozone => _metrics[AirQualityMetric.ozone];
  AirQualityParameter get pm2_5 => _metrics[AirQualityMetric.pm2_5];
  AirQualityParameter get pm10 => _metrics[AirQualityMetric.pm10];
  AirQualityParameter get carbonMonoxide => _metrics[AirQualityMetric.carbonMonoxide];
  AirQualityParameter get nitrogenDioxide => _metrics[AirQualityMetric.nitrogenDioxide];
  AirQualityParameter get sulphurDioxide => _metrics[AirQualityMetric.sulphurDioxide];
  Map<AirQualityMetric, AirQualityParameter> _metrics;

  @override
  String toString() {
    StringBuffer result = new StringBuffer();
    DateTime stamp = timestamp;
    if (stamp == null)
      result.write('$earliestTimestamp - $latestTimestamp');
    else
      result.write('$stamp');
    Set<AirQualityStation> stations = new HashSet<AirQualityStation>();
    int count = 0;
    for (AirQualityMetric metric in AirQualityMetric.values) {
      AirQualityParameter parameter = _metrics[metric];
      if (parameter != null) {
        result.write('  ');
        result.write(parameter.toString());
        stations.add(parameter.station);
        count += 1;
      }
    }
    if (count == 0) {
      for (AirQualityParameter parameter in _parameters) {
        result.write('  ');
        result.write(parameter.toString());
        stations.add(parameter.station);
        count += 1;
      }
    }
    if (count > 0) {
      String suffix;
      int missed = _parameters.length - count;
      if (missed > 0) {
        suffix = '; $missed more data point${ missed == 1 ? "" : "s" } omitted';
      } else {
        suffix = '';
      }
      result.write('  (${stations.toList().join(', ')}$suffix)');
    } else {
      result.write('  no data');
    }
    return result.toString();
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

/// See https://docs.airnowapi.org/Data/query
class AirQualityMonitor {
  AirQualityMonitor({ @required GeoBox area, @required String apiKey, this.onLog }) {
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
