import 'dart:collection';

import 'package:meta/meta.dart';

import 'common.dart';
import 'hash_codes.dart';
import 'temperature.dart';
import 'radiation.dart';

// MeasurementPacket has a list of Measurements, each of which has a MeasurementStation.
// Measurements include AirQualityParameters, Radiation, and Temperature (the latter two defined in their own files; see above).

class MeasurementStation {
  const MeasurementStation({ this.latitude, this.longitude, this.siteName, this.agencyName, this.aqsCode, this.internationalAqsCode, this.corrected: false, this.outside = false });

  final double latitude;
  final double longitude;
  final String siteName;
  final String agencyName;
  final String aqsCode;
  final String internationalAqsCode;
  final bool corrected;
  final bool outside;

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
    bool outside,
  }) {
    return new MeasurementStation(
      latitude: latitude ?? this.latitude, 
      longitude: longitude ?? this.longitude, 
      siteName: siteName ?? this.siteName, 
      agencyName: agencyName ?? this.agencyName, 
      aqsCode: aqsCode ?? this.aqsCode, 
      internationalAqsCode: internationalAqsCode ?? this.internationalAqsCode, 
      corrected: corrected ?? this.corrected,
      outside: outside ?? this.outside,
    );
  }

  @override
  int get hashCode => hashValues(latitude, longitude, siteName, agencyName, aqsCode, internationalAqsCode, corrected, outside);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    final MeasurementStation typedOther = other;
    return typedOther.latitude == latitude
        && typedOther.longitude == longitude
        && typedOther.siteName == siteName
        && typedOther.agencyName == agencyName
        && typedOther.aqsCode == aqsCode
        && typedOther.internationalAqsCode == internationalAqsCode
        && typedOther.corrected == corrected
        && typedOther.outside == outside;
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
  pm1_0,
  pressure,
  radiation,
  sulphurDioxide,
  temperature,
  volatileOrganicCompounds,
}

String metricToString(Metric metric) {
  switch (metric) {
    case Metric.carbonDioxide:
      return 'CO₂';
    case Metric.carbonMonoxide:
      return 'CO';
    case Metric.formaldehyde:
      return 'CH₂O';
    case Metric.humidity:
      return 'Humidity';
    case Metric.nitrogenDioxide:
      return 'NO₂';
    case Metric.noise:
      return 'Noise';
    case Metric.ozone:
      return 'O₃';
    case Metric.pm10:
      return 'PM₁₀';
    case Metric.pm2_5:
      return 'PM₂.₅';
    case Metric.pm1_0:
      return 'PM₁.₀';
    case Metric.pressure:
      return 'Pressure';
    case Metric.radiation:
      return 'Radiation';
    case Metric.sulphurDioxide:
      return 'SO₂';
    case Metric.temperature:
      return 'Temperature';
    case Metric.volatileOrganicCompounds:
      return 'VOC';
  }
  return null;
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
    double aqi,
  }) : _aqi = aqi,
       super(station: station, timestamp: timestamp) {
    assert(station != null);
    assert(timestamp != null);
    assert(metric != null);
    assert(units != null);
  }

  AirQualityParameter.humidity(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.humidity,
       units = MetricUnits.relativeHumidity,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pressure(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.pressure,
       units = MetricUnits.pascals,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.volatileOrganicCompounds(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.volatileOrganicCompounds,
       units = MetricUnits.ohm, // MetricUnits.milligramsPerCubicMeter,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.carbonMonoxide(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.carbonMonoxide,
       units = MetricUnits.partsPerMillion,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.carbonDioxide(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.carbonDioxide,
       units = MetricUnits.partsPerMillion,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.noise(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.noise,
       units = MetricUnits.decibels,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.formaldehyde(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.formaldehyde,
       units = MetricUnits.partsPerMillion,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pm10(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.pm10,
       units = MetricUnits.microgramsPerCubicMeter,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pm2_5(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.pm2_5,
       units = MetricUnits.microgramsPerCubicMeter,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.pm1_0(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.pm1_0,
       units = MetricUnits.microgramsPerCubicMeter,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  AirQualityParameter.ozone(this.value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
    double aqi,
  }) : metric = Metric.ozone,
       units = MetricUnits.partsPerBillion,
       _aqi = aqi,
       super(station: station, timestamp: timestamp);

  @override
  final Metric metric;

  @override
  final double value;

  @override
  final MetricUnits units;

  double get aqi {
    if (_aqi != null)
      return _aqi;
    // This is based on:
    //   https://aqicn.org/calculator
    //   https://aqs.epa.gov/aqsweb/documents/codetables/aqi_breakpoints.html
    switch (metric) {
      case Metric.pm2_5:
        assert(units == MetricUnits.microgramsPerCubicMeter);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 12.0, 35.5, 55.5, 150.5, 250.5, 350.5, 500.0],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        );
      case Metric.pm10:
        assert(units == MetricUnits.microgramsPerCubicMeter);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 55.0, 155.0, 255.0, 355.0, 425.0, 505.0, 605.0],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        );
      case Metric.carbonMonoxide:
        assert(units == MetricUnits.partsPerMillion);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 4.5, 9.5, 12.5, 15.5, 30.5, 40.5, 50.5],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        );
      case Metric.nitrogenDioxide:
        assert(units == MetricUnits.partsPerBillion);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 0.054, 0.101, 0.361, 0.65, 1.25, 1.65, 2.049],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        );
      case Metric.ozone:
        // This is based on the 8h average AQI breakpoints from the
        // EPA, but generally we have instantaneous numbers so...
        // BTW, when updating this, be careful with the units. People
        // measure this in ppb but breakpoints seem to be defined in ppm.
        assert(units == MetricUnits.partsPerBillion);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 54.0, 70.0, 85.0, 105.0, 200.0],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0],
        );
        // 1h average numbers:
        // return interpolateWithPoints(
        //   input: value,
        //   inputStopPoints: <double>[0.0, 124.0, 164.0, 204.0, 404.0, 504.0, 604.0],
        //   aqiStopPoints: <double>[0.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        // );
      case Metric.sulphurDioxide:
        // range 0..200 is based on the 1hr average, 200..500 is based on 24h average.
        // despite this we apply it to instantaneous numbers
        assert(units == MetricUnits.partsPerBillion);
        return interpolateWithPoints(
          input: value,
          inputStopPoints: <double>[0.0, 36.0, 76.0, 186.0, 304.0, 605.0, 805.0, 1004.0],
          aqiStopPoints: <double>[0.0, 50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0],
        );
      default:
        return null;
    }
  }
  final double _aqi;

  static double interpolateWithPoints({ double input, List<double> inputStopPoints, List<double> aqiStopPoints }) {
    assert(inputStopPoints.length == aqiStopPoints.length);
    assert(inputStopPoints.length >= 2);
    final int length = inputStopPoints.length;
    if (input < inputStopPoints.first) {
      return interpolate(input, inputStopPoints[0], inputStopPoints[1], aqiStopPoints[0], aqiStopPoints[1]);
    } else if (input > inputStopPoints.last) {
      return interpolate(input, inputStopPoints[length - 2], inputStopPoints[length - 1], aqiStopPoints[length - 2], aqiStopPoints[length - 1]);
    } else {
      for (int index = 1; index < length; index += 1) {
        if (input < inputStopPoints[index])
          return interpolate(input, inputStopPoints[index - 1], inputStopPoints[index], aqiStopPoints[index - 1], aqiStopPoints[index]);
      }
    }
    assert(false);
    return null;
  }

  static double interpolate(double input, double inA, double inB, double outA, double outB) {
    return ((outB - outA) * ((input - inA) / (inB - inA))) + outA;
  }

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

  @override
  int get hashCode => hashValues(station, timestamp, metric, value, units, aqi);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    final AirQualityParameter typedOther = other;
    return typedOther.station == station
        && typedOther.timestamp == timestamp
        && typedOther.metric == metric
        && typedOther.value == value
        && typedOther.units == units
        && typedOther.aqi == aqi;
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
  AirQualityParameter get pm1_0 => _metrics[Metric.pm1_0] as AirQualityParameter;
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
        result.write(metricToString(parameter.metric));
        result.write(': ');
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

  @override
  int get hashCode => hashList(parameters);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    final MeasurementPacket typedOther = other;
    return listEquals<Measurement>(typedOther.parameters, parameters);
  }
}
