import 'dart:collection';

import 'package:meta/meta.dart';

import 'common.dart';
import 'hash_codes.dart';
import 'temperature.dart';
import 'radiation.dart';

class MeasurementStation {
  const MeasurementStation({ this.latitude, this.longitude, this.siteName, this.agencyName, this.aqsCode, this.internationalAqsCode, this.corrected: false });

  final double latitude;
  final double longitude;
  final String siteName;
  final String agencyName;
  final String aqsCode;
  final String internationalAqsCode;
  final bool corrected;

  @override
  String toString() {
    String result = siteName ?? agencyName ?? aqsCode ?? internationalAqsCode ?? '$latitude,$longitude';
    if (corrected)
      result = '$result (with adjustments)';
    return result;
  }

  MeasurementStation copyWith({
    double latitude,
    double longitude,
    String siteName,
    String agencyName,
    String aqsCode,
    String internationalAqsCode,
    bool corrected,
  }) {
    return new MeasurementStation(
      latitude: latitude ?? this.latitude, 
      longitude: longitude ?? this.longitude, 
      siteName: siteName ?? this.siteName, 
      agencyName: agencyName ?? this.agencyName, 
      aqsCode: aqsCode ?? this.aqsCode, 
      internationalAqsCode: internationalAqsCode ?? this.internationalAqsCode, 
      corrected: corrected ?? this.corrected, 
    );
  }

  @override
  int get hashCode => hashValues(latitude, longitude, siteName, agencyName, aqsCode, internationalAqsCode, corrected);

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType)
      return false;
    MeasurementStation typedOther = other;
    return typedOther.latitude == latitude
        && typedOther.longitude == longitude
        && typedOther.siteName == siteName
        && typedOther.agencyName == agencyName
        && typedOther.aqsCode == aqsCode
        && typedOther.internationalAqsCode == internationalAqsCode
        && typedOther.corrected == corrected;
  }
}

enum Metric {
  carbonDioxide,
  carbonMonoxide,
  formaldehyde,
  humidity,
  nitrogenDioxide,
  noise,
  ozone,
  pm10,
  pm2_5,
  pressure,
  radiation,
  sulphurDioxide,
  temperature,
  volatileOrganicCompounds,
}

@immutable
abstract class Measurement {
  Measurement({
    @required this.station,
    @required this.timestamp,
  }) {
    assert(station != null);
  }

  final MeasurementStation station;
  final DateTime timestamp;

  Metric get metric;

  double get value;
  MetricUnits get units;

  @override
  String toString() {
    StringBuffer result = new StringBuffer();
    if (value != null) {
      result.write(value.toStringAsFixed(2));
      switch (units) {
        case MetricUnits.celsius:
          result.write('℃');
          break;
        case MetricUnits.decibels:
          result.write('dB');
          break;
        case MetricUnits.fahrenheit:
          result.write('℉');
          break;
        case MetricUnits.microgramsPerCubicMeter:
          result.write('µg/m³');
          break;
        case MetricUnits.microsievertsPerHour:
          result.write('μSv/h');
          break;
        case MetricUnits.milligramsPerCubicMeter:
          result.write('mg/m³');
          break;
        case MetricUnits.ohm:
          result.write('Ω');
          break;
        case MetricUnits.partsPerBillion:
          result.write('ppb');
          break;
        case MetricUnits.partsPerMillion:
          result.write('ppm');
          break;
        case MetricUnits.pascals:
          result.write('Pa');
          break;
        case MetricUnits.relativeHumidity:
          result.write('RH');
          break;
      }
    } else {
      result.write('unknown');
    }
    return result.toString();
  }
}

enum MetricUnits {
  celsius,
  decibels,
  fahrenheit,
  microgramsPerCubicMeter,
  microsievertsPerHour,
  milligramsPerCubicMeter,
  ohm,
  partsPerBillion,
  partsPerMillion,
  pascals,
  relativeHumidity,
}

class AirQualityParameter extends Measurement {
  AirQualityParameter({
    @required MeasurementStation station,
    @required DateTime timestamp,
    @required this.metric,
    @required this.units,
    @required this.value,
    this.aqi,
  }) : super(station: station, timestamp: timestamp) {
    assert(station != null);
    assert(timestamp != null);
    assert(metric != null);
    assert(units != null);
  }

  AirQualityParameter.humidity(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.humidity,
       units = MetricUnits.relativeHumidity,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pressure(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.pressure,
       units = MetricUnits.pascals,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.volatileOrganicCompounds(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.volatileOrganicCompounds,
       units = MetricUnits.ohm, // MetricUnits.milligramsPerCubicMeter,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.carbonDioxide(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.carbonDioxide,
       units = MetricUnits.partsPerMillion,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.noise(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.noise,
       units = MetricUnits.decibels,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.formaldehyde(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.formaldehyde,
       units = MetricUnits.partsPerMillion,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pm2_5(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    this.aqi,
  }) : metric = Metric.pm2_5,
       units = MetricUnits.microgramsPerCubicMeter,
       super(station: station, timestamp: timestamp);

  @override
  final Metric metric;

  @override
  final double value;

  @override
  final MetricUnits units;

  final double aqi;

  @override
  String toString() {
    final StringBuffer result = new StringBuffer();
    result.write(super.toString());
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

class MeasurementPacket {
  MeasurementPacket(List<Measurement> parameters) {
    _parameters = parameters;
    _stations = new HashSet<MeasurementStation>();
    _metrics = new HashMap<Metric, Measurement>();
    for (Measurement parameter in parameters) {
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

  Iterable<Measurement> get parameters => _parameters;
  List<Measurement> _parameters;

  Iterable<MeasurementStation> get stations => _stations;
  Set<MeasurementStation> _stations;

  AirQualityParameter get carbonDioxide => _metrics[Metric.carbonDioxide] as AirQualityParameter;
  AirQualityParameter get carbonMonoxide => _metrics[Metric.carbonMonoxide] as AirQualityParameter;
  AirQualityParameter get formaldehyde => _metrics[Metric.formaldehyde] as AirQualityParameter;
  AirQualityParameter get humidity => _metrics[Metric.humidity] as AirQualityParameter;
  AirQualityParameter get nitrogenDioxide => _metrics[Metric.nitrogenDioxide] as AirQualityParameter;
  AirQualityParameter get noise => _metrics[Metric.noise] as AirQualityParameter;
  AirQualityParameter get ozone => _metrics[Metric.ozone] as AirQualityParameter;
  AirQualityParameter get pm10 => _metrics[Metric.pm10] as AirQualityParameter;
  AirQualityParameter get pm2_5 => _metrics[Metric.pm2_5] as AirQualityParameter;
  AirQualityParameter get pressure => _metrics[Metric.pressure] as AirQualityParameter;
  Radiation get radiation => _metrics[Metric.radiation] as Radiation;
  AirQualityParameter get sulphurDioxide => _metrics[Metric.sulphurDioxide] as AirQualityParameter;
  Temperature get temperature => _metrics[Metric.temperature] as Temperature;
  AirQualityParameter get volatileOrganicCompounds => _metrics[Metric.volatileOrganicCompounds] as AirQualityParameter;
  Map<Metric, Measurement> _metrics;

  @override
  String toString() {
    if (_parameters.isEmpty)
      return 'no data';
    StringBuffer result = new StringBuffer();
    DateTime stamp = timestamp;
    if (stamp == null)
      result.write('$earliestTimestamp - $latestTimestamp');
    else
      result.write('$stamp');
    Set<MeasurementStation> stations = new HashSet<MeasurementStation>();
    int count = 0;
    for (Metric metric in Metric.values) {
      Measurement parameter = _metrics[metric];
      if (parameter != null) {
        result.write('  ');
        switch (metric) {
          case Metric.carbonDioxide:
            result.write('CO₂: ');
            break;
          case Metric.carbonMonoxide:
            result.write('CO: ');
            break;
          case Metric.formaldehyde:
            result.write('CH₂O: ');
            break;
          case Metric.humidity:
            result.write('Humidity: ');
            break;
          case Metric.nitrogenDioxide:
            result.write('NO₂: ');
            break;
          case Metric.noise:
            result.write('Noise: ');
            break;
          case Metric.ozone:
            result.write('O₃: ');
            break;
          case Metric.pm10:
            result.write('PM₁₀: ');
            break;
          case Metric.pm2_5:
            result.write('PM₂.₅: ');
            break;
          case Metric.pressure:
            result.write('Pressure: ');
            break;
          case Metric.radiation:
            result.write('Radiation: ');
            break;
          case Metric.sulphurDioxide:
            result.write('SO₂: ');
            break;
          case Metric.temperature:
            result.write('Temperature: ');
            break;
          case Metric.volatileOrganicCompounds:
            result.write('VOC: ');
            break;
        }
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
